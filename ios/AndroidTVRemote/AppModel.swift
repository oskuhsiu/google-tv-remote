import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: RemoteState = .idle
    @Published private(set) var rememberedRecord: LastTvRecord?
    @Published private(set) var diagnosticMessage: String?
    @Published private(set) var keepReadyEnabled: Bool
    @Published private(set) var keepAliveStatus: KeepAliveStatus
    @Published private(set) var voiceState: VoiceState = .unavailable
    @Published private(set) var voiceMessage: String?

    private let discovery: DiscoveryControlling
    private let session: RemoteSessionControlling
    private let identity: ClientIdentityValidating
    private let store: LastTvStoring
    private let backgroundKeepAlive: BackgroundKeepAliveControlling
    private let persistKeepReady: (Bool) -> Void
    private let retrySleep: (TimeInterval) async throws -> Void
    private var sceneIsActive = false
    private var sessionEventsAllowed = false
    private var disconnectedByUser = false
    private var securityStoreBlocked = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectFailureReason: RemoteError?
    private var microphonePermissionTask: Task<Void, Never>?

    var canConnectRemembered: Bool {
        rememberedRecord != nil && !securityStoreBlocked
    }

    var keepReadyAvailable: Bool {
        backgroundKeepAlive.isAvailable
    }

    var widgetSnapshot: WidgetRemoteSnapshot {
        let tvName = rememberedRecord?.name
        let availability: WidgetRemoteAvailability
        switch state {
        case .connected:
            availability = widgetSessionIsReachable ? .ready : .unavailable
        case .connecting, .reconnecting:
            availability = .connecting
        default:
            availability = .unavailable
        }
        return WidgetRemoteSnapshot(tvName: tvName, availability: availability)
    }

    private var widgetSessionIsReachable: Bool {
        sceneIsActive || (
            keepReadyAvailable &&
                keepReadyEnabled &&
                (keepAliveStatus == .starting || keepAliveStatus == .ready)
        )
    }

    init(
        discovery: DiscoveryControlling,
        session: RemoteSessionControlling,
        identity: ClientIdentityValidating,
        store: LastTvStoring,
        backgroundKeepAlive: BackgroundKeepAliveControlling? = nil,
        initialKeepReadyEnabled: Bool = false,
        persistKeepReady: @escaping (Bool) -> Void = { _ in },
        retrySleep: @escaping (TimeInterval) async throws -> Void = { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.discovery = discovery
        self.session = session
        self.identity = identity
        self.store = store
        let backgroundKeepAlive = backgroundKeepAlive ?? DisabledBackgroundKeepAliveController()
        self.backgroundKeepAlive = backgroundKeepAlive
        self.keepReadyEnabled = initialKeepReadyEnabled && backgroundKeepAlive.isAvailable
        self.keepAliveStatus = backgroundKeepAlive.status
        self.persistKeepReady = persistKeepReady
        self.retrySleep = retrySleep

        discovery.onCandidatesChanged = { [weak self] candidates in
            guard let self, self.sceneIsActive, self.rememberedRecord == nil else { return }
            self.state = .discovering(candidates)
        }
        session.onEvent = { [weak self] event in
            self?.handleSessionEvent(event)
        }
        session.onVoiceStateChanged = { [weak self] state in
            self?.voiceState = state
            if state == .listening {
                self?.voiceMessage = nil
            }
        }
        session.onVoiceError = { [weak self] error in
            self?.handleVoiceError(error)
        }
        backgroundKeepAlive.onStatusChanged = { [weak self] status in
            self?.keepAliveStatus = status
        }
        restoreRememberedTV()
    }

    func enterForeground() {
        let wasActive = sceneIsActive
        sceneIsActive = true
        sessionEventsAllowed = true
        backgroundKeepAlive.stop()

        if securityStoreBlocked {
            return
        }

        guard !wasActive else { return }
        switch state {
        case .connected, .connecting, .reconnecting:
            disconnectedByUser = false
            return
        default:
            break
        }

        let action = ForegroundPolicy.action(
            alreadyActive: wasActive,
            hasValidPairing: rememberedRecord != nil
        )
        guard action != .none else { return }

        disconnectedByUser = false
        cancelReconnect()
        switch action {
        case .connectRemembered:
            discovery.stop()
            guard let rememberedRecord else { return }
            state = .connecting(rememberedRecord.device)
            session.connect(to: rememberedRecord)
        case .startDiscovery:
            state = .discovering([])
            discovery.start()
        case .none:
            break
        }
    }

    func enterBackground() {
        guard sceneIsActive else { return }
        stopVoice()
        sceneIsActive = false
        discovery.stop()

        let isConnected: Bool
        if case .connected = state {
            isConnected = true
        } else {
            isConnected = false
        }

        switch BackgroundSessionPolicy.action(
            keepReadyEnabled: keepReadyEnabled,
            keepAliveAvailable: keepReadyAvailable,
            hasValidPairing: rememberedRecord != nil,
            isConnected: isConnected,
            disconnectedByUser: disconnectedByUser
        ) {
        case .retainConnectedSession:
            sessionEventsAllowed = true
            backgroundKeepAlive.start()
        case .disconnect:
            sessionEventsAllowed = false
            cancelReconnect()
            backgroundKeepAlive.stop()
            session.disconnect()
            if let rememberedRecord {
                state = .disconnected(rememberedRecord.device)
            } else {
                state = .idle
            }
        }
    }

    func disconnect() {
        guard sceneIsActive else { return }
        stopVoice()
        disconnectedByUser = true
        sessionEventsAllowed = false
        cancelReconnect()
        discovery.stop()
        backgroundKeepAlive.stop()
        session.disconnect()
        state = .disconnected(rememberedRecord?.device)
    }

    func forget() {
        stopVoice()
        sessionEventsAllowed = false
        cancelReconnect()
        discovery.stop()
        backgroundKeepAlive.stop()
        session.disconnect()
        do {
            try identity.deleteIdentity()
        } catch {
            diagnosticMessage = "The saved identity could not be removed. Try Forget again."
            state = .failed(rememberedRecord?.device, reason: .unknown, recoverable: true)
            return
        }
        store.clear()
        rememberedRecord = nil
        disconnectedByUser = false
        securityStoreBlocked = false

        if ForegroundPolicy.allowsAutomaticDiscovery(
            isActive: sceneIsActive,
            hasValidPairing: false
        ) {
            sessionEventsAllowed = true
            state = .discovering([])
            discovery.start()
        } else {
            state = .idle
        }
    }

    func connectRemembered() {
        guard sceneIsActive, !securityStoreBlocked, let rememberedRecord else { return }
        disconnectedByUser = false
        sessionEventsAllowed = true
        cancelReconnect()
        discovery.stop()
        state = .connecting(rememberedRecord.device)
        session.connect(to: rememberedRecord)
    }

    func requestCompactRemote() {
        guard sceneIsActive, canConnectRemembered else { return }
        switch state {
        case .connected, .connecting, .reconnecting:
            return
        default:
            connectRemembered()
        }
    }

    func setKeepReadyEnabled(_ enabled: Bool) {
        guard !enabled || keepReadyAvailable else { return }
        guard keepReadyEnabled != enabled else { return }
        keepReadyEnabled = enabled
        persistKeepReady(enabled)

        guard !enabled else { return }
        backgroundKeepAlive.stop()
        if !sceneIsActive {
            sessionEventsAllowed = false
            cancelReconnect()
            session.disconnect()
            state = rememberedRecord.map { .disconnected($0.device) } ?? .idle
        }
    }

    func send(_ command: RemoteCommand, action: RemoteKeyAction = .short) {
        guard case .connected = state else { return }
        session.send(command: command, action: action)
    }

    func startVoice() {
        guard case .connected = state,
              voiceState == .idle,
              microphonePermissionTask == nil else {
            return
        }

        voiceMessage = nil
        voiceState = .starting
        microphonePermissionTask = Task { [weak self] in
            let granted = await MicrophonePermission.request()
            guard let self else { return }
            let wasCancelled = Task.isCancelled
            self.microphonePermissionTask = nil
            guard !wasCancelled,
                  case .connected = self.state,
                  self.voiceState == .starting else {
                return
            }
            guard granted else {
                self.voiceState = .idle
                self.voiceMessage = "Allow microphone access in Settings to use voice search."
                return
            }
            self.session.startVoice()
        }
    }

    func stopVoice() {
        let wasRequestingPermission = microphonePermissionTask != nil
        microphonePermissionTask?.cancel()
        microphonePermissionTask = nil
        session.stopVoice()
        if wasRequestingPermission, case .connected = state, voiceState == .starting {
            voiceState = .idle
        }
    }

    func enterInactive() {
        stopVoice()
    }

    @discardableResult
    func sendWidgetCommand(_ command: WidgetRemoteCommand) -> Bool {
        guard case .connected = state, widgetSessionIsReachable else { return false }
        session.send(command: command.remoteCommand, action: .short)
        return true
    }

    private func handleSessionEvent(_ event: RemoteSessionEvent) {
        guard sessionEventsAllowed, !disconnectedByUser else { return }
        switch event {
        case .connected(let device):
            cancelReconnect()
            state = .connected(device)
            if !sceneIsActive, keepReadyEnabled {
                backgroundKeepAlive.start()
            }
        case .failed(let device, let reason, let recoverable):
            if reason == .pairingRequired, let device {
                cancelReconnect()
                backgroundKeepAlive.stop()
                sessionEventsAllowed = sceneIsActive
                state = .needsPairing(device)
            } else if shouldReconnect(after: reason),
                      let record = rememberedRecord,
                      device?.id == record.persistentDeviceID {
                scheduleReconnect(record: record, reason: reason)
            } else {
                cancelReconnect()
                backgroundKeepAlive.stop()
                sessionEventsAllowed = sceneIsActive
                state = .failed(device, reason: reason, recoverable: recoverable)
            }
        }
    }

    private func shouldReconnect(after reason: RemoteError) -> Bool {
        reason == .networkUnreachable || reason == .connectionLost
    }

    private func handleVoiceError(_ error: RemoteError) {
        switch error {
        case .voicePermissionDenied:
            voiceMessage = "Allow microphone access in Settings to use voice search."
        case .voiceSessionFailed:
            voiceMessage = "Voice search could not start. Try again."
        default:
            voiceMessage = "Voice search is unavailable. Try again."
        }
    }

    private func scheduleReconnect(record: LastTvRecord, reason: RemoteError) {
        reconnectFailureReason = reason
        guard reconnectAttempt < ReconnectPolicy.delays.count else {
            let terminalReason = reconnectFailureReason ?? reason
            cancelReconnect()
            backgroundKeepAlive.stop()
            sessionEventsAllowed = sceneIsActive
            state = .failed(record.device, reason: terminalReason, recoverable: true)
            return
        }

        let attempt = reconnectAttempt + 1
        reconnectAttempt = attempt
        reconnectTask?.cancel()
        state = .reconnecting(record.device, attempt: attempt)
        let delay = ReconnectPolicy.delays[attempt - 1]
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.retrySleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self.connectionWorkAllowed,
                  !self.disconnectedByUser,
                  self.rememberedRecord == record else {
                return
            }
            self.session.connect(to: record)
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        reconnectFailureReason = nil
    }

    private var connectionWorkAllowed: Bool {
        sceneIsActive || (keepReadyEnabled && sessionEventsAllowed && rememberedRecord != nil)
    }

    private func restoreRememberedTV() {
        let candidate: LastTvRecord?
        do {
            candidate = try store.load()
        } catch {
            recoverFromInvalidMetadata()
            return
        }

        guard let candidate else {
            do {
                try identity.deleteIdentity()
            } catch {
                blockForSecurityStoreFailure()
            }
            return
        }

        do {
            rememberedRecord = candidate
            guard candidate.isComplete else {
                try clearInvalidTuple()
                return
            }
            switch try identity.status(matching: candidate.clientIdentityFingerprint) {
            case .matches:
                rememberedRecord = candidate
            case .missing, .mismatch:
                try clearInvalidTuple()
            }
        } catch {
            blockForSecurityStoreFailure()
        }
    }

    private func recoverFromInvalidMetadata() {
        do {
            try identity.deleteIdentity()
            store.clear()
            rememberedRecord = nil
            diagnosticMessage = "Saved TV data was invalid and has been cleared."
        } catch {
            blockForSecurityStoreFailure()
        }
    }

    private func blockForSecurityStoreFailure() {
        diagnosticMessage = "Saved TV security data is unavailable. Try again before pairing."
        securityStoreBlocked = true
        state = .failed(rememberedRecord?.device, reason: .unknown, recoverable: true)
    }

    private func clearInvalidTuple() throws {
        try identity.deleteIdentity()
        store.clear()
        rememberedRecord = nil
    }
}

private extension WidgetRemoteCommand {
    var remoteCommand: RemoteCommand {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .select: .select
        case .back: .back
        case .home: .home
        }
    }
}
