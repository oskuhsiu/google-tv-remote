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
    private var isActive = false
    private var disconnectedByUser = false
    private var securityStoreBlocked = false

    init(
        discovery: DiscoveryControlling,
        session: RemoteSessionControlling,
        identity: ClientIdentityValidating,
        store: LastTvStoring
    ) {
        self.discovery = discovery
        self.session = session
        self.identity = identity
        self.store = store

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
        discovery.stop()
        session.disconnect()
        state = .disconnected(rememberedRecord?.device)
    }

    func forget() {
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
        guard isActive, let rememberedRecord else { return }
        discovery.stop()
        state = .connecting(rememberedRecord.device)
        session.connect(to: rememberedRecord)
    }

    func send(_ command: RemoteCommand, action: RemoteKeyAction = .short) {
        guard case .connected = state else { return }
        session.send(command: command, action: action)
    }

    func markConnected(to device: RemoteDevice) {
        guard isActive, !disconnectedByUser else { return }
        state = .connected(device)
    }

    private func handleSessionEvent(_ event: RemoteSessionEvent) {
        guard isActive, !disconnectedByUser else { return }
        switch event {
        case .connected(let device):
            state = .connected(device)
        case .failed(let device, let reason, let recoverable):
            state = .failed(device, reason: reason, recoverable: recoverable)
        }
    }

    private func restoreRememberedTV() {
        do {
            guard let candidate = try store.load() else { return }
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
            diagnosticMessage = "Saved TV security data is unavailable. Try again before pairing."
            securityStoreBlocked = true
            state = .failed(nil, reason: .unknown, recoverable: true)
        }
    }

    private func clearInvalidTuple() throws {
        try identity.deleteIdentity()
        store.clear()
        rememberedRecord = nil
    }
}
