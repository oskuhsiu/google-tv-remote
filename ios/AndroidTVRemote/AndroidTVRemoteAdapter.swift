import AndroidTVRemoteControl
import Foundation
import Security
import SwiftProtobuf

@MainActor
final class AndroidTVRemoteAdapter: RemoteSessionControlling {
    var onEvent: ((RemoteSessionEvent) -> Void)?

    private let identityStore: IdentityStore
    private var remoteManager: RemoteManager?
    private var writer: OutboundWriter?
    private var trustGate: PeerTrustGate?
    private var connectingDevice: RemoteDevice?
    private var didReachConnectedState = false
    private var sessionGeneration = 0
    private var sendTail: Task<Void, Never>?

    init(identityStore: IdentityStore) {
        self.identityStore = identityStore
    }

    func connect(to record: LastTvRecord) {
        let device = record.device
        guard record.isComplete else {
            onEvent?(.failed(device, reason: .trustChanged, recoverable: false))
            return
        }
        disconnect()

        do {
            guard let identity = try identityStore.load(),
                  identity.fingerprint == record.clientIdentityFingerprint else {
                onEvent?(.failed(device, reason: .trustChanged, recoverable: false))
                return
            }
            let gate = PeerTrustGate(expectedFingerprint: record.remotePeerFingerprint)
            let tlsManager = TLSManager { .Result(identity.tlsImportItems) }
            tlsManager.secTrustClosure = { trust in
                gate.evaluate(trust)
            }

            let deviceInfo = CommandNetwork.DeviceInfo(
                "iPhone",
                "Apple",
                "1.0.0",
                "dev.local.AndroidTVRemote",
                "1"
            )
            let manager = RemoteManager(tlsManager, deviceInfo, nil)
            manager.stateChanged = { [weak self, weak manager] state in
                Task { @MainActor in
                    guard let self, self.remoteManager === manager else { return }
                    self.handle(state, device: device, gate: gate)
                }
            }

            connectingDevice = device
            didReachConnectedState = false
            trustGate = gate
            remoteManager = manager
            writer = OutboundWriter { [weak manager] frame in
                guard let manager else { throw AdapterError.sessionUnavailable }
                manager.send(frame)
            }
            manager.connect(device.host, timeout: 8)
        } catch {
            tearDown()
            onEvent?(.failed(device, reason: .unknown, recoverable: true))
        }
    }

    func disconnect() {
        sessionGeneration &+= 1
        sendTail?.cancel()
        sendTail = nil
        remoteManager?.stateChanged = nil
        remoteManager?.frameReceived = nil
        remoteManager?.receiveData = nil
        remoteManager?.disconnect()
        tearDown()
    }

    func send(command: RemoteCommand, action: RemoteKeyAction) {
        guard command.supports(action), let writer else { return }
        do {
            let payload = try RemotePayloadFactory.key(command: command, action: action)
            let generation = sessionGeneration
            let previous = sendTail
            let task = Task { [weak self] in
                if let previous { await previous.value }
                guard !Task.isCancelled else { return }
                do {
                    try await writer.send(payload: payload)
                } catch {
                    guard let self, self.sessionGeneration == generation else { return }
                    self.onEvent?(
                        .failed(self.connectingDevice, reason: .connectionLost, recoverable: true)
                    )
                }
            }
            sendTail = task
        } catch {
            onEvent?(.failed(connectingDevice, reason: .unknown, recoverable: true))
        }
    }

    private func handle(
        _ state: RemoteManager.RemoteState,
        device: RemoteDevice,
        gate: PeerTrustGate
    ) {
        switch state {
        case .paired:
            guard gate.isAccepted else {
                disconnect()
                onEvent?(.failed(device, reason: .trustChanged, recoverable: false))
                return
            }
            didReachConnectedState = true
            onEvent?(.connected(device))

        case .error(let error):
            let result = AdapterErrorPolicy.failure(
                error: error,
                for: gate.outcome,
                device: device,
                wasConnected: didReachConnectedState
            )
            disconnect()
            onEvent?(result)

        case .idle, .connectionSetUp, .connectionPrepairing, .connected,
             .fisrtConfigMessageReceived, .firstConfigSent, .secondConfigSent:
            break
        }
    }

    private func tearDown() {
        remoteManager = nil
        writer = nil
        trustGate = nil
        connectingDevice = nil
        didReachConnectedState = false
    }
}

enum AdapterError: Error {
    case sessionUnavailable
    case unsupportedKeyCode(Int)
}

enum RemotePayloadFactory {
    static func key(command: RemoteCommand, action: RemoteKeyAction) throws -> Data {
        guard command.supports(action),
              let keyCode = Remote_RemoteKeyCode(rawValue: command.androidKeyCode) else {
            throw AdapterError.unsupportedKeyCode(command.androidKeyCode)
        }

        var key = Remote_RemoteKeyInject()
        key.keyCode = keyCode
        key.direction = action.remoteDirection

        var message = Remote_RemoteMessage()
        message.remoteKeyInject = key
        return try message.serializedData()
    }
}

private extension RemoteKeyAction {
    var remoteDirection: Remote_RemoteDirection {
        switch self {
        case .short: .short
        case .startLong: .startLong
        case .endLong: .endLong
        }
    }
}

enum PeerTrustOutcome: Equatable {
    case notEvaluated
    case accepted(String)
    case missingCertificate
    case changed(expected: String, actual: String)
}

final class PeerTrustGate: @unchecked Sendable {
    private let expectedFingerprint: String
    private let lock = NSLock()
    private var storedOutcome: PeerTrustOutcome = .notEvaluated

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint.lowercased()
    }

    var outcome: PeerTrustOutcome {
        lock.lock()
        defer { lock.unlock() }
        return storedOutcome
    }

    var isAccepted: Bool {
        if case .accepted = outcome { return true }
        return false
    }

    func evaluate(_ trust: SecTrust) -> Bool {
        guard let certificate = CertificateFingerprint.leafCertificate(from: trust) else {
            setOutcome(.missingCertificate)
            return false
        }
        let actual = CertificateFingerprint.sha256(certificate)
        let accepted = Self.accepts(expected: expectedFingerprint, actual: actual)
        setOutcome(
            accepted
                ? .accepted(actual)
                : .changed(expected: expectedFingerprint, actual: actual)
        )
        return accepted
    }

    static func accepts(expected: String, actual: String) -> Bool {
        !expected.isEmpty && expected.caseInsensitiveCompare(actual) == .orderedSame
    }

    private func setOutcome(_ value: PeerTrustOutcome) {
        lock.lock()
        storedOutcome = value
        lock.unlock()
    }
}

enum AdapterErrorPolicy {
    static func failure(
        error: AndroidTVRemoteControlError,
        for outcome: PeerTrustOutcome,
        device: RemoteDevice,
        wasConnected: Bool = false
    ) -> RemoteSessionEvent {
        switch outcome {
        case .changed:
            return .failed(device, reason: .trustChanged, recoverable: false)
        case .accepted, .notEvaluated, .missingCertificate:
            break
        }

        switch error {
        case .connectionFailed, .connectionWaitingError:
            if wasConnected {
                return .failed(device, reason: .connectionLost, recoverable: true)
            }
            return .failed(device, reason: .networkUnreachable, recoverable: true)

        case .receiveDataError, .sendDataError, .connectionCanceled, .connectionClosed:
            return .failed(
                device,
                reason: wasConnected ? .connectionLost : .networkUnreachable,
                recoverable: true
            )

        case .invalidFrame:
            return .failed(device, reason: .unknown, recoverable: true)

        case .unexpectedCertData, .extractCFTypeRefError, .secIdentityCreateError,
             .toLongNames, .pairingNotSuccess, .optionNotSuccess,
             .configurationNotSuccess, .secretNotSuccess, .invalidCode,
             .wrongCode, .noSecAttributes, .notRSAKey, .notPublicKey,
             .noKeySizeAttribute, .noValueData, .invalidCertData,
             .createCertFromDataError, .noClientPublicCertificate,
             .noServerPublicCertificate, .secTrustCopyKeyError,
             .loadCertFromURLError, .secPKCS12ImportNotSuccess,
             .createTrustObjectError, .secTrustCreateWithCertificatesNotSuccess:
            return .failed(device, reason: .unknown, recoverable: false)
        }
    }

}
