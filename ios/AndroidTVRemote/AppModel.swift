import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: RemoteState = .idle
    @Published private(set) var rememberedRecord: LastTvRecord?
    @Published private(set) var diagnosticMessage: String?

    private let discovery: DiscoveryControlling
    private let session: RemoteSessionControlling
    private let identity: ClientIdentityValidating
    private let store: LastTvStoring
    private let retrySleep: (TimeInterval) async throws -> Void
    private var isActive = false
    private var disconnectedByUser = false
    private var securityStoreBlocked = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectFailureReason: RemoteError?

    var canConnectRemembered: Bool {
        rememberedRecord != nil && !securityStoreBlocked
    }

    init(
        discovery: DiscoveryControlling,
        session: RemoteSessionControlling,
        identity: ClientIdentityValidating,
        store: LastTvStoring,
        retrySleep: @escaping (TimeInterval) async throws -> Void = { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.discovery = discovery
        self.session = session
        self.identity = identity
        self.store = store
        self.retrySleep = retrySleep

        discovery.onCandidatesChanged = { [weak self] candidates in
            guard let self, self.isActive, self.rememberedRecord == nil else { return }
            self.state = .discovering(candidates)
        }
        session.onEvent = { [weak self] event in
            self?.handleSessionEvent(event)
        }
        restoreRememberedTV()
    }

    func enterForeground() {
        if securityStoreBlocked {
            isActive = true
            return
        }
        let action = ForegroundPolicy.action(
            alreadyActive: isActive,
            hasValidPairing: rememberedRecord != nil
        )
        guard action != .none else { return }

        isActive = true
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
        guard isActive else { return }
        isActive = false
        cancelReconnect()
        discovery.stop()
        session.disconnect()
        if let rememberedRecord {
            state = .disconnected(rememberedRecord.device)
        } else {
            state = .idle
        }
    }

    func disconnect() {
        guard isActive else { return }
        disconnectedByUser = true
        cancelReconnect()
        discovery.stop()
        session.disconnect()
        state = .disconnected(rememberedRecord?.device)
    }

    func forget() {
        cancelReconnect()
        discovery.stop()
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

        if ForegroundPolicy.allowsAutomaticDiscovery(isActive: isActive, hasValidPairing: false) {
            state = .discovering([])
            discovery.start()
        } else {
            state = .idle
        }
    }

    func connectRemembered() {
        guard isActive, !securityStoreBlocked, let rememberedRecord else { return }
        disconnectedByUser = false
        cancelReconnect()
        discovery.stop()
        state = .connecting(rememberedRecord.device)
        session.connect(to: rememberedRecord)
    }

    func send(_ command: RemoteCommand, action: RemoteKeyAction = .short) {
        guard case .connected = state else { return }
        session.send(command: command, action: action)
    }

    private func handleSessionEvent(_ event: RemoteSessionEvent) {
        guard isActive, !disconnectedByUser else { return }
        switch event {
        case .connected(let device):
            cancelReconnect()
            state = .connected(device)
        case .failed(let device, let reason, let recoverable):
            if reason == .pairingRequired, let device {
                cancelReconnect()
                state = .needsPairing(device)
            } else if shouldReconnect(after: reason),
                      let record = rememberedRecord,
                      device?.id == record.persistentDeviceID {
                scheduleReconnect(record: record, reason: reason)
            } else {
                cancelReconnect()
                state = .failed(device, reason: reason, recoverable: recoverable)
            }
        }
    }

    private func shouldReconnect(after reason: RemoteError) -> Bool {
        reason == .networkUnreachable || reason == .connectionLost
    }

    private func scheduleReconnect(record: LastTvRecord, reason: RemoteError) {
        reconnectFailureReason = reason
        guard reconnectAttempt < ReconnectPolicy.delays.count else {
            let terminalReason = reconnectFailureReason ?? reason
            cancelReconnect()
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
                  self.isActive,
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
