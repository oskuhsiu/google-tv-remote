//
//  PairingManager.swift
//  
//
//  Created by Roman Odyshew on 15.10.2023.
//

import Foundation
import Network
import CryptoKit

public class PairingManager {
    private let stateQueue = DispatchQueue(label: "pairing.state")
    private let connectQueue = DispatchQueue(label: "pairing.connect")
    
    private var pairingResponse = PairingNetwork.PairingResponse()
    private var optionResponse = PairingNetwork.OptionResponse()
    private var configResponse = PairingNetwork.ConfigurationResponse()
    
    private var connection: NWConnection?
    private var cryptoManager: CryptoManager
    private let tlsManager: TLSManager
    private let frameDecoder = VarintFrameDecoder()
    
    private var clientName = "client"
    private var serviceName = "service"
    private var code: String = ""
    
    public var logger: Logger?
    private let logPrefix = "Pairing: "
    
    public var stateChanged: ((PairingState)->())?
    /// Called once for each complete length-delimited protobuf payload.
    public var frameReceived: ((Data)->Void)?
    
    private var pairingState: PairingState = .idle {
        didSet {
            let state = pairingState
            
            stateQueue.async {
                switch state {
                case .idle:
                    self.logger?.infoLog(self.logPrefix + "idle")
                case .extractTLSparams:
                    self.logger?.infoLog(self.logPrefix + "extract TLS parameters")
                case .connectionSetUp:
                    self.logger?.infoLog(self.logPrefix + "connection set up")
                case .connectionPrepairing:
                    self.logger?.infoLog(self.logPrefix + "connection prepairing")
                case .connected:
                    self.logger?.infoLog(self.logPrefix + "connected")
                case .pairingRequestSent:
                    self.logger?.infoLog(self.logPrefix + "pairing request has been sent")
                case .pairingResponseSuccess:
                    self.logger?.infoLog(self.logPrefix + "pairing sesponse success")
                case .optionRequestSent:
                    self.logger?.infoLog(self.logPrefix + "option request sent")
                case .optionResponseSuccess:
                    self.logger?.infoLog(self.logPrefix + "option response success")
                case .confirmationRequestSent:
                    self.logger?.infoLog(self.logPrefix + "confirmation request has been sent")
                case .confirmationResponseSuccess:
                    self.logger?.infoLog(self.logPrefix + "confirmation response success")
                case .waitingCode:
                    self.logger?.infoLog(self.logPrefix + "waiting code")
                case .secretSent:
                    self.logger?.infoLog(self.logPrefix + "secret has been sent")
                case .successPaired:
                    self.logger?.infoLog(self.logPrefix + "success paired")
                case .error(let error):
                    self.logger?.errorLog(self.logPrefix + error.localizedDescription)
                }
                
                self.stateChanged?(state)
            }
        }
    }
    
    public init(_ tlsManager: TLSManager, _ cryptoManager: CryptoManager, _ logger: Logger? = nil) {
        self.tlsManager = tlsManager
        self.cryptoManager = cryptoManager
        self.logger = logger
    }
    
    public func connect(_ host: String, _ clientName: String, _ serviceName: String, timeout: Int = 60) {
        if host.isEmpty {
            logger?.errorLog(logPrefix + "host shouldn't be empty!")
        }
        
        self.clientName = clientName
        self.serviceName = serviceName
        frameDecoder.reset()
        
        pairingState = .extractTLSparams
        
        let tlsParams: NWParameters

        switch tlsManager.getNWParams(connectQueue, timeout: timeout) {
        case .Result(let params):
            tlsParams = params
        case .Error(let error):
            pairingState = .error(error)
            return
        }
        
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: 6467),
            using: tlsParams)
        
        connection?.stateUpdateHandler = handleConnectionState
        logger?.infoLog(logPrefix + "connecting " + host + ":6467")
        connection?.start(queue: connectQueue)
    }
    
    public func disconnect() {
        logger?.infoLog(logPrefix + "disconnect")
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
    
    public func sendSecret(_ code: String) {
        // Set the code for secret transmission
        self.code = code
        let secret: [UInt8]
        switch cryptoManager.getEncodedCert(code) {
        case .Result(let data):
            secret = data
        case .Error(let error):
            pairingState = .error(error)
            disconnect()
            return
        }
        
        send(PairingNetwork.SecretRequest(encodedCert: secret))
        pairingState = .secretSent
        
        receive()
    }
    
    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .setup:
            pairingState = .connectionSetUp
        case .waiting(let error):
            pairingState = .error(.connectionWaitingError(error))
            disconnect()
        case .preparing:
            pairingState = .connectionPrepairing
        case .ready:
            pairingState = .connected
            
            pairingResponse = PairingNetwork.PairingResponse()
            logger?.debugLog(logPrefix + "Sending pairing request")
            send(PairingNetwork.PairingRequest(clientName: clientName, serviceName: serviceName))
            pairingState = .pairingRequestSent
            
            receive()
        case .failed(let error):
            pairingState = .error(.connectionFailed(error))
            disconnect()
        case .cancelled:
            pairingState = .error(.connectionCanceled)
            disconnect()
        default:
            break
        }
    }
    
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] (data, context, isComplete, error) in
            guard let `self` = self else { return }
            
            if let error = error {
                self.pairingState = .error(.receiveDataError(error))
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if !isComplete {
                    self.receive()
                }
                return
            }

            do {
                for frame in try self.frameDecoder.append(data) {
                    self.frameReceived?(frame)
                    self.handle(frame)
                }
            } catch {
                self.pairingState = .error(.invalidFrame(error))
                self.disconnect()
                return
            }

            if !isComplete && self.shouldContinueReceiving {
                self.receive()
            }
        }
    }

    private var shouldContinueReceiving: Bool {
        switch pairingState {
        case .waitingCode, .successPaired, .error:
            return false
        default:
            return true
        }
    }

    private func handle(_ data: Data) {
        switch pairingState {
            case .pairingRequestSent:
                pairingResponse.length = Data(Encoder.encodeVarint(UInt(data.count)))
                pairingResponse.data = data
                guard pairingResponse.isSuccess else {
                    pairingState = .error(.pairingNotSuccess(data))
                    return
                }

                pairingState = .pairingResponseSuccess
                optionResponse = PairingNetwork.OptionResponse()
                logger?.debugLog(self.logPrefix + "Sending option request")
                send(PairingNetwork.OptionRequest())
                pairingState = .optionRequestSent

            case .optionRequestSent:
                optionResponse.length = Data(Encoder.encodeVarint(UInt(data.count)))
                optionResponse.data = data
                guard optionResponse.isSuccess else {
                    pairingState = .error(.optionNotSuccess(data))
                    return
                }

                pairingState = .optionResponseSuccess
                configResponse = PairingNetwork.ConfigurationResponse()
                logger?.debugLog(self.logPrefix + "Sending configuration request")
                send(PairingNetwork.ConfigurationRequest())
                pairingState = .confirmationRequestSent

            case .confirmationRequestSent:
                configResponse.length = Data(Encoder.encodeVarint(UInt(data.count)))
                configResponse.data = data
                guard configResponse.isSuccess else {
                    pairingState = .error(.configurationNotSuccess(data))
                    return
                }

                pairingState = .confirmationResponseSuccess
                pairingState = .waitingCode

            case .secretSent:
                let framedData = VarintFrameEncoder.frame(data)
                let secretResponse = PairingNetwork.SecretResponse(data: framedData, code: code)
                pairingState = secretResponse.isSuccess ? .successPaired : .error(.secretNotSuccess(data))
                self.disconnect()

            default:
                break
        }
    }
    
    private func send(_ request: RequestDataProtocol) {
        send(VarintFrameEncoder.frame(request.data))
    }

    private func send(_ data: Data) {
        connectQueue.async { [weak self] in
            guard let self = self else { return }
            self.connection?.send(content: data, completion: .contentProcessed({ [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    self.pairingState = .error(.sendDataError(error))
                    self.disconnect()
                }
            }))
        }
    }
}

extension PairingManager {
   public enum PairingState {
        case idle
        case extractTLSparams
        case connectionSetUp
        case connectionPrepairing
        case connected
        case pairingRequestSent
        case pairingResponseSuccess
        case optionRequestSent
        case optionResponseSuccess
        case confirmationRequestSent
        case confirmationResponseSuccess
        case waitingCode
        case secretSent
        case successPaired
        case error(AndroidTVRemoteControlError)
    }
}
