//
//  RemoteManager.swift
//  
//
//  Created by Roman Odyshew on 15.10.2023.
//

import Foundation
import Network

public class RemoteManager {
    private let stateQueue = DispatchQueue(label: "remote.state")
    private let remoteQueue = DispatchQueue(label: "remote.connect")
    private let receiveQueue = DispatchQueue(label: "remote.receive")
    
    private var connection: NWConnection?
    private let tlsManager: TLSManager
    private let frameDecoder = VarintFrameDecoder()
    private var secondConfigurationResponse = SecondConfigurationResponse()
    
    public var stateChanged: ((RemoteState)->())?
    public var receiveData: ((Data?, Error?)->Void)?
    /// Called once for each complete length-delimited protobuf payload.
    public var frameReceived: ((Data)->Void)?
    public var deviceInfo: CommandNetwork.DeviceInfo
    
    public var logger: Logger?
    private let logPrefix = "Remote: "
    
    private var remoteState: RemoteState = .idle {
        didSet {
            let state = remoteState
            
            stateQueue.async {
                switch state {
                case .error(let error):
                    self.logger?.errorLog(self.logPrefix + error.localizedDescription)
                case .connected:
                    self.logger?.infoLog(self.logPrefix + "connected")
                case .idle:
                    self.logger?.infoLog(self.logPrefix + "idle")
                case .connectionSetUp:
                    self.logger?.infoLog(self.logPrefix + "connection set up")
                case .connectionPrepairing:
                    self.logger?.infoLog(self.logPrefix + "connection preparing")
                case .fisrtConfigMessageReceived(let info):
                    self.logger?.infoLog(self.logPrefix + String(format: "fisrt configuration message has been received: %@ %@ %@ %@ %@", info.vendor, info.model, info.appName, info.appBuild, info.version))
                case .firstConfigSent:
                    self.logger?.infoLog(self.logPrefix + "fisrt configuration has been sent")
                case .secondConfigSent:
                    self.logger?.infoLog(self.logPrefix + "second configuration has been sent")
                case .paired(runningApp: let runningApp):
                    self.logger?.infoLog(self.logPrefix + "paired, current running app: " + (runningApp ?? "Unknown"))
                }
                
                self.stateChanged?(state)
            }
        }
    }
    
    public init(_ tlsManager: TLSManager, _ deviceInfo: CommandNetwork.DeviceInfo, _ logger: Logger? = nil) {
        self.tlsManager = tlsManager
        self.deviceInfo = deviceInfo
        self.logger = logger
    }
    
    public func connect(_ host: String, timeout: Int = 60) {
        if host.isEmpty {
            logger?.errorLog(logPrefix + "host shouldn't be empty!")
        }
        
        frameDecoder.reset()
        let tlsParams: NWParameters

        switch tlsManager.getNWParams(remoteQueue, timeout: timeout) {
        case .Result(let params):
            tlsParams = params
        case .Error(let error):
            remoteState = .error(error)
            return
        }
        
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: 6466),
            using: tlsParams)
        
        connection?.stateUpdateHandler = handleConnectionState
        logger?.infoLog(logPrefix + "connecting " + host + ":6466")
        secondConfigurationResponse = SecondConfigurationResponse()
        connection?.start(queue: remoteQueue)
    }
    
    public func disconnect() {
        logger?.infoLog(logPrefix + "disconnect")
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
    
    public func send(_ request: RequestDataProtocol) {
        send(VarintFrameEncoder.frame(request.data))
    }
    
    public func send(_ data: Data, _ nextData: Data? = nil) {
        var atomicData = data
        if let nextData = nextData {
            atomicData.append(nextData)
        }

        remoteQueue.async { [weak self] in
            guard let self = self else { return }
            self.connection?.send(content: atomicData, completion: .contentProcessed({ [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    self.remoteState = .error(.sendDataError(error))
                    self.disconnect()
                }
            }))
        }
    }
    
    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .setup:
            remoteState = .connectionSetUp
        case .waiting(let error):
            remoteState = .error(.connectionWaitingError(error))
            disconnect()
        case .preparing:
            remoteState = .connectionPrepairing
        case .ready:
            remoteState = .connected
            receive()
        case .failed(let error):
            remoteState = .error(.connectionFailed(error))
            disconnect()
        case .cancelled:
            remoteState = .error(.connectionCanceled)
            disconnect()
        default:
            break
        }
    }
    
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] (data, context, isComplete, error) in
            guard let `self` = self else { return }
            
            self.receiveQueue.async {
                self.receiveData?(data, error)
            }
            
            if let error = error {
                remoteState = .error(.receiveDataError(error))
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if !isComplete {
                    self.receive()
                }
                return
            }

            do {
                for payload in try self.frameDecoder.append(data) {
                    self.frameReceived?(payload)
                    self.handleFrame(VarintFrameEncoder.frame(payload))
                }
            } catch {
                self.remoteState = .error(.invalidFrame(error))
                self.disconnect()
                return
            }

            if !isComplete {
                self.receive()
            }
        }
    }
    
    private func handleFrame(_ data: Data) {
        if handlePing(data) {
            return
        }
        
        switch remoteState {
        case .connected:
            guard let configMessage = CommandNetwork.AndroidTVConfigurationMessage(data) else {
                logger?.debugLog(logPrefix + "it's not configuration message")
                return
            }

            remoteState = .fisrtConfigMessageReceived(configMessage.deviceInfo)
            
            secondConfigurationResponse.modelName = configMessage.deviceInfo.model
            
            logger?.debugLog(logPrefix + "Sending first configuration request")
            send(CommandNetwork.FirstConfigurationRequest(deviceInfo: deviceInfo))
            remoteState = .firstConfigSent

        case .firstConfigSent:
            guard CommandNetwork.FirstConfigurationResponse(data: data).isSuccess else {
                logger?.debugLog(logPrefix + "it's not first configuration response")
                return
            }
            
            logger?.debugLog(logPrefix + "first configuration response was received")
            logger?.debugLog(logPrefix + "Sending second configuration request")
            send(CommandNetwork.SecondConfigurationRequest())
            remoteState = .secondConfigSent

        case .secondConfigSent:
            guard secondConfigurationResponse.parse(data) else {
                logger?.debugLog(logPrefix + "it's not second configuration response")
                return
            }
            
            if secondConfigurationResponse.currentAppPart {
                logger?.debugLog(logPrefix + "second configuration response CURRENT APP - OK")
            }
            
            if secondConfigurationResponse.powerPart {
                logger?.debugLog(logPrefix + "second configuration response POWER - OK")
            }
            
            if secondConfigurationResponse.volumeLevelPart {
                logger?.debugLog(logPrefix + "second configuration response VOLUME LEVEL - OK")
            }
            
            guard secondConfigurationResponse.readyFullResponse else {
                return
            }
            
            remoteState = .paired(runningApp: secondConfigurationResponse.runAppName)
        default:
            logger?.debugLog(logPrefix + "unrecognized data")
            _ = VolumeLevel(data)
        }
    }
    
    private func handlePing(_ data: Data) -> Bool {
        guard let ping = CommandNetwork.Ping.extract(from: data) else {
            return false
        }
        
        logger?.debugLog(logPrefix + "ping has bin handled")
        let pong = CommandNetwork.Pong(ping.val1)
        logger?.debugLog(logPrefix + "sending pong")
        send(pong.data)
        return true
    }
}

extension RemoteManager {
    public enum RemoteState {
        case idle
        case connectionSetUp
        case connectionPrepairing
        case connected
        case fisrtConfigMessageReceived(CommandNetwork.DeviceInfo)
        case firstConfigSent
        case secondConfigSent
        case paired(runningApp: String?)
        case error(AndroidTVRemoteControlError)
    }
}
