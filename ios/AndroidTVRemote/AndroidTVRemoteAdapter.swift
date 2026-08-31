import AndroidTVRemoteControl
import Foundation
import Security
import SwiftProtobuf

@MainActor
final class AndroidTVRemoteAdapter: RemoteSessionControlling {
    var onEvent: ((RemoteSessionEvent) -> Void)?
    var onVoiceStateChanged: ((VoiceState) -> Void)?
    var onVoiceError: ((RemoteError) -> Void)?

    private let identityStore: IdentityStore
    private var remoteManager: RemoteManager?
    private var writer: OutboundWriter?
    private var trustGate: PeerTrustGate?
    private var connectingDevice: RemoteDevice?
    private var didReachConnectedState = false
    private var sessionGeneration = 0
    private var sendTail: Task<Void, Never>?
    private var voiceSupported = false
    private var voiceGeneration = 0
    private var activeVoiceRun: VoiceRun?
    private var voiceTask: Task<Void, Never>?

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
            manager.frameReceived = { [weak self, weak manager] payload in
                Task { @MainActor in
                    guard let self, self.remoteManager === manager else { return }
                    self.handleInboundFrame(payload)
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
        cancelVoiceForDisconnect()
        sessionGeneration &+= 1
        sendTail?.cancel()
        sendTail = nil
        remoteManager?.stateChanged = nil
        remoteManager?.frameReceived = nil
        remoteManager?.receiveData = nil
        remoteManager?.disconnect()
        tearDown()
        onVoiceStateChanged?(.unavailable)
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
                    try writer.send(payload: payload)
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

    func startVoice() {
        guard didReachConnectedState, voiceSupported, activeVoiceRun == nil else {
            onVoiceError?(.voiceSessionFailed)
            return
        }

        voiceGeneration &+= 1
        let run = VoiceRun(generation: voiceGeneration)
        activeVoiceRun = run
        onVoiceStateChanged?(.starting)
        voiceTask = Task { [weak self] in
            await self?.performVoiceStart(run)
        }
    }

    func stopVoice() {
        guard let run = activeVoiceRun else { return }
        run.stopRequested = true

        if let capture = run.capture {
            let finalChunk = capture.stop()
            finishVoice(run, finalChunk: finalChunk, sendEnd: !run.remoteEnded)
        } else if run.didSendBegin {
            finishVoice(run, finalChunk: nil, sendEnd: !run.remoteEnded)
        } else {
            finishVoice(run, finalChunk: nil, sendEnd: false)
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
            onVoiceStateChanged?(voiceSupported ? .idle : .unavailable)
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

    private func performVoiceStart(_ run: VoiceRun) async {
        do {
            if let sendTail {
                await sendTail.value
            }
            try requireCurrentVoiceRun(run)
            guard let writer else { throw AdapterError.sessionUnavailable }
            try writer.send(payload: RemotePayloadFactory.voiceSearch())

            let sessionID = try await waitForVoiceBegin(run)
            try requireCurrentVoiceRun(run)
            run.sessionID = sessionID
            try writer.send(
                payload: RemotePayloadFactory.voiceBegin(sessionID: sessionID)
            )
            run.didSendBegin = true

            if run.stopRequested {
                finishVoice(run, finalChunk: nil, sendEnd: true)
                return
            }

            let capture = VoiceCapture()
            run.capture = capture
            let generation = run.generation
            try capture.start(
                onChunk: { [weak self] chunk in
                    Task { @MainActor in
                        self?.sendVoiceChunk(chunk, generation: generation)
                    }
                },
                onFailure: { [weak self] _ in
                    Task { @MainActor in
                        self?.voiceCaptureFailed(generation: generation)
                    }
                }
            )

            if run.stopRequested {
                let finalChunk = capture.stop()
                finishVoice(run, finalChunk: finalChunk, sendEnd: true)
            } else {
                onVoiceStateChanged?(.listening)
            }
        } catch is CancellationError {
            finishVoice(run, finalChunk: nil, sendEnd: run.didSendBegin && !run.remoteEnded)
        } catch {
            if run.stopRequested {
                finishVoice(run, finalChunk: nil, sendEnd: run.didSendBegin && !run.remoteEnded)
            } else {
                failVoice(run)
            }
        }
    }

    private func waitForVoiceBegin(_ run: VoiceRun) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            guard activeVoiceRun === run else {
                continuation.resume(throwing: CancellationError())
                return
            }
            run.beginContinuation = continuation
            run.beginTimeoutTask = Task { [weak self, weak run] in
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
                guard let self, let run else { return }
                self.voiceBeginTimedOut(run)
            }
        }
    }

    private func voiceBeginTimedOut(_ run: VoiceRun) {
        guard activeVoiceRun === run, let continuation = run.beginContinuation else { return }
        run.beginContinuation = nil
        continuation.resume(throwing: AdapterError.voiceBeginTimedOut)
    }

    private func sendVoiceChunk(_ chunk: Data, generation: Int) {
        guard let run = activeVoiceRun,
              run.generation == generation,
              !run.stopRequested,
              !run.remoteEnded,
              run.didSendBegin,
              let sessionID = run.sessionID,
              let writer else {
            return
        }

        do {
            try writer.send(
                payload: RemotePayloadFactory.voicePayload(
                    sessionID: sessionID,
                    samples: chunk
                )
            )
        } catch {
            failVoice(run)
        }
    }

    private func voiceCaptureFailed(generation: Int) {
        guard let run = activeVoiceRun, run.generation == generation else { return }
        failVoice(run)
    }

    private func failVoice(_ run: VoiceRun) {
        guard activeVoiceRun === run else { return }
        run.stopRequested = true
        _ = run.capture?.stop()
        finishVoice(run, finalChunk: nil, sendEnd: run.didSendBegin && !run.remoteEnded)
        onVoiceError?(.voiceSessionFailed)
    }

    private func finishVoice(_ run: VoiceRun, finalChunk: Data?, sendEnd: Bool) {
        guard activeVoiceRun === run else { return }

        run.beginTimeoutTask?.cancel()
        run.beginTimeoutTask = nil
        if let continuation = run.beginContinuation {
            run.beginContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        _ = run.capture?.stop()
        run.capture = nil

        if sendEnd, let sessionID = run.sessionID, let writer {
            if let finalChunk {
                try? writer.send(
                    payload: RemotePayloadFactory.voicePayload(
                        sessionID: sessionID,
                        samples: finalChunk
                    )
                )
            }
            try? writer.send(
                payload: RemotePayloadFactory.voiceEnd(sessionID: sessionID)
            )
        }

        activeVoiceRun = nil
        voiceTask = nil
        onVoiceStateChanged?(didReachConnectedState && voiceSupported ? .idle : .unavailable)
    }

    private func cancelVoiceForDisconnect() {
        voiceGeneration &+= 1
        guard let run = activeVoiceRun else {
            voiceTask?.cancel()
            voiceTask = nil
            return
        }

        run.stopRequested = true
        let finalChunk = run.capture?.stop()
        let task = voiceTask
        finishVoice(
            run,
            finalChunk: finalChunk,
            sendEnd: run.didSendBegin && !run.remoteEnded
        )
        task?.cancel()
    }

    private func requireCurrentVoiceRun(_ run: VoiceRun) throws {
        guard activeVoiceRun === run, run.generation == voiceGeneration else {
            throw CancellationError()
        }
    }

    private func handleInboundFrame(_ payload: Data) {
        guard let message = try? Remote_RemoteMessage(serializedBytes: payload) else { return }

        if message.hasRemoteConfigure {
            voiceSupported = (message.remoteConfigure.code1 & RemotePayloadFactory.voiceFeature) != 0
            if didReachConnectedState, activeVoiceRun == nil {
                onVoiceStateChanged?(voiceSupported ? .idle : .unavailable)
            }
        }

        if message.hasRemoteVoiceBegin,
           let run = activeVoiceRun,
           let continuation = run.beginContinuation {
            run.beginContinuation = nil
            run.beginTimeoutTask?.cancel()
            run.beginTimeoutTask = nil
            run.sessionID = message.remoteVoiceBegin.sessionID
            continuation.resume(returning: message.remoteVoiceBegin.sessionID)
        }

        if message.hasRemoteVoiceEnd,
           let run = activeVoiceRun,
           run.sessionID == message.remoteVoiceEnd.sessionID {
            run.remoteEnded = true
            run.stopRequested = true
            _ = run.capture?.stop()
            finishVoice(run, finalChunk: nil, sendEnd: false)
        }
    }

    private func tearDown() {
        remoteManager = nil
        writer = nil
        trustGate = nil
        connectingDevice = nil
        didReachConnectedState = false
        voiceSupported = false
    }
}

private final class VoiceRun {
    let generation: Int
    var stopRequested = false
    var remoteEnded = false
    var sessionID: Int32?
    var didSendBegin = false
    var capture: VoiceCapture?
    var beginContinuation: CheckedContinuation<Int32, Error>?
    var beginTimeoutTask: Task<Void, Never>?

    init(generation: Int) {
        self.generation = generation
    }
}

enum AdapterError: Error {
    case sessionUnavailable
    case unsupportedKeyCode(Int)
    case voiceBeginTimedOut
    case voicePayloadTooLarge(Int)
}

enum RemotePayloadFactory {
    static let voiceFeature: Int32 = 1 << 3
    static let maximumVoicePayloadByteCount = 20_480

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

    static func voiceSearch() throws -> Data {
        try key(keyCode: 84, action: .short)
    }

    static func voiceBegin(sessionID: Int32) throws -> Data {
        var begin = Remote_RemoteVoiceBegin()
        begin.sessionID = sessionID
        var message = Remote_RemoteMessage()
        message.remoteVoiceBegin = begin
        return try message.serializedData()
    }

    static func voicePayload(sessionID: Int32, samples: Data) throws -> Data {
        guard samples.count <= maximumVoicePayloadByteCount else {
            throw AdapterError.voicePayloadTooLarge(samples.count)
        }
        var payload = Remote_RemoteVoicePayload()
        payload.sessionID = sessionID
        payload.samples = samples
        var message = Remote_RemoteMessage()
        message.remoteVoicePayload = payload
        return try message.serializedData()
    }

    static func voiceEnd(sessionID: Int32) throws -> Data {
        var end = Remote_RemoteVoiceEnd()
        end.sessionID = sessionID
        var message = Remote_RemoteMessage()
        message.remoteVoiceEnd = end
        return try message.serializedData()
    }

    private static func key(keyCode: Int, action: RemoteKeyAction) throws -> Data {
        guard let keyCode = Remote_RemoteKeyCode(rawValue: keyCode) else {
            throw AdapterError.unsupportedKeyCode(keyCode)
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
