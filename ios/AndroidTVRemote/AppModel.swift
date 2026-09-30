import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: RemoteState = .idle
    @Published private(set) var rememberedRecord: LastTvRecord?
    @Published private(set) var diagnosticMessage: String?
    @Published private(set) var discoveryMessage: String?
    @Published private(set) var keepReadyEnabled: Bool
    @Published private(set) var keepAliveStatus: KeepAliveStatus
    @Published private(set) var voiceState: VoiceState = .unavailable
    @Published private(set) var voiceMessage: String?
    @Published private(set) var networkWakeMessage: String?
    @Published private(set) var isTestingNetworkWake = false

    private let discovery: DiscoveryControlling
    private let session: RemoteSessionControlling
    private let identity: ClientIdentityValidating
    private let store: LastTvStoring
    private let backgroundKeepAlive: BackgroundKeepAliveControlling
    private let persistKeepReady: (Bool) -> Void
    private let retrySleep: (TimeInterval) async throws -> Void
    private let wolSender: WolSending
    private var networkWakeTask: Task<Void, Never>?
    private var networkWakeGeneration = 0
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
        wolSender: WolSending = LocalNetworkWolSender(),
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
        self.wolSender = wolSender
        let backgroundKeepAlive = backgroundKeepAlive ?? DisabledBackgroundKeepAliveController()
        self.backgroundKeepAlive = backgroundKeepAlive
        self.keepReadyEnabled = initialKeepReadyEnabled && backgroundKeepAlive.isAvailable
        self.keepAliveStatus = backgroundKeepAlive.status
        self.persistKeepReady = persistKeepReady
        self.retrySleep = retrySleep

        discovery.onCandidatesChanged = { [weak self] candidates in
            guard let self, self.sceneIsActive, self.rememberedRecord == nil else { return }
            if !candidates.isEmpty {
                self.discoveryMessage = nil
            }
            self.state = .discovering(candidates)
        }
        discovery.onErrorChanged = { [weak self] error in
            guard let self, self.sceneIsActive, self.rememberedRecord == nil else { return }
            self.discoveryMessage = error == nil
                ? nil
                : "Local network access is unavailable. Check Local Network permission in Settings, then retry."
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
        cancelNetworkWakeTest()
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
        cancelNetworkWakeTest()
        networkWakeMessage = nil
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

    func retryDiscovery() {
        guard sceneIsActive, rememberedRecord == nil else { return }
        discoveryMessage = nil
        state = .discovering([])
        discovery.stop()
        discovery.start()
    }

    func selectDiscoveredTV(_ candidate: TvCandidate) {
        guard sceneIsActive, rememberedRecord == nil else { return }
        discovery.stop()
        discoveryMessage = nil
        diagnosticMessage = nil

        let locatorParts = candidate.locatorKey.split(
            separator: "|",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        let locator = locatorParts.count == 3
            ? BonjourLocator(
                domain: String(locatorParts[0]),
                type: String(locatorParts[1]),
                name: String(locatorParts[2])
            )
            : nil
        let device = RemoteDevice(
            id: candidate.locatorKey,
            name: candidate.name,
            host: candidate.host,
            locator: locator,
            source: candidate.source
        )
        sessionEventsAllowed = true
        state = .pairing(device)
        session.startPairing(with: device)
    }

    func submitPairingCode(_ code: String) {
        guard sceneIsActive,
              case .needsPairing(let device) = state,
              let normalizedCode = PairingCodeValidator.normalized(code) else {
            return
        }
        diagnosticMessage = nil
        state = .pairing(device)
        session.submitPairingCode(normalizedCode)
    }

    func cancelPairing() {
        guard sceneIsActive, rememberedRecord == nil else { return }
        session.disconnect()
        state = .discovering([])
        discovery.start()
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

    @discardableResult
    func saveNetworkWakeMAC(_ input: String) -> Bool {
        guard canConnectRemembered, var record = rememberedRecord else { return false }
        guard let settings = NetworkWakeSettings(macAddress: input) else {
            networkWakeMessage = NSLocalizedString("Enter a valid device MAC address, such as A4:77:33:12:AB:CD.", comment: "Invalid wake MAC")
            return false
        }
        cancelNetworkWakeTest()
        record.networkWake = settings
        return persistNetworkWake(record, message: "MAC saved. Wake support is unverified.")
    }

    @discardableResult
    func clearNetworkWakeMAC() -> Bool {
        guard canConnectRemembered, var record = rememberedRecord else { return false }
        cancelNetworkWakeTest()
        record.networkWake = nil
        return persistNetworkWake(record, message: "MAC address cleared.")
    }

    private func persistNetworkWake(_ record: LastTvRecord, message: String) -> Bool {
        do {
            try store.save(record)
            rememberedRecord = record
            networkWakeMessage = NSLocalizedString(message, comment: "Wake settings feedback")
            return true
        } catch {
            networkWakeMessage = NSLocalizedString("Could not save the MAC address. Try again.", comment: "Wake storage error")
            return false
        }
    }

    @discardableResult
    func testNetworkWake() -> Task<Void, Never>? {
        guard sceneIsActive, canConnectRemembered, !isTestingNetworkWake,
              let record = rememberedRecord, let settings = record.networkWake else { return nil }
        networkWakeMessage = nil
        isTestingNetworkWake = true
        networkWakeGeneration += 1
        let generation = networkWakeGeneration
        networkWakeTask = Task { [weak self, wolSender] in
            defer {
                if let self, self.networkWakeGeneration == generation {
                    self.isTestingNetworkWake = false
                    self.networkWakeTask = nil
                }
            }
            let message: String
            do {
                try await wolSender.send(macAddress: settings.macAddress)
                message = "Wake packet sent. This does not confirm that the TV woke."
            } catch is CancellationError {
                return
            } catch WolSendError.localNetworkUnavailable {
                message = "Connect your iPhone to the same local Wi-Fi or Ethernet network as the TV. VPN and cellular connections cannot send this test."
            } catch {
                message = "Could not send the wake packet. Check Local Network permission and your Wi-Fi connection, then try again."
            }
            guard let self, !Task.isCancelled, self.networkWakeGeneration == generation,
                  let current = self.rememberedRecord, current.hasSameTrust(as: record),
                  current.networkWake == settings else { return }
            self.isTestingNetworkWake = false
            self.networkWakeTask = nil
            self.networkWakeMessage = NSLocalizedString(message, comment: "Wake packet test result")
        }
        return networkWakeTask
    }

    func cancelNetworkWakeTest() {
        networkWakeGeneration += 1
        networkWakeTask?.cancel()
        networkWakeTask = nil
        isTestingNetworkWake = false
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
        case .pairingCodeRequested(let device):
            state = .needsPairing(device)
        case .pairingCompleted(let incomingRecord):
            var record = incomingRecord
            if let current = rememberedRecord, current.hasSameTrust(as: record) {
                record.networkWake = current.networkWake
            }
            do {
                try store.save(record)
                rememberedRecord = record
                state = .connected(record.device)
            } catch {
                sessionEventsAllowed = false
                session.disconnect()
                diagnosticMessage = "The paired TV could not be saved. Forget it on the TV and try again."
                state = .failed(record.device, reason: .unknown, recoverable: true)
            }
        case .connected(let device):
            cancelReconnect()
            state = .connected(device)
            if !sceneIsActive, keepReadyEnabled {
                backgroundKeepAlive.start()
            }
        case .failed(let device, let reason, let recoverable):
            if rememberedRecord == nil, sceneIsActive {
                cancelReconnect()
                backgroundKeepAlive.stop()
                diagnosticMessage = pairingFailureMessage(for: reason)
                    ?? "Could not connect to the TV. Select it and try again."
                state = .discovering([])
                discovery.start()
            } else if reason == .pairingRequired, let device {
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
                diagnosticMessage = pairingFailureMessage(for: reason)
                state = .failed(device, reason: reason, recoverable: recoverable)
            }
        }
    }

    private func pairingFailureMessage(for reason: RemoteError) -> String? {
        switch reason {
        case .pairingCodeInvalid:
            return "That pairing code was not accepted. Select the TV and try again."
        case .pairingRejected:
            return "The TV rejected pairing. Select it and try again."
        case .pairingTimeout:
            return "Pairing timed out. Select the TV and try again."
        default:
            return nil
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
                  let currentRecord = self.rememberedRecord,
                  currentRecord.hasSameTrust(as: record) else {
                return
            }
            self.session.connect(to: currentRecord)
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
