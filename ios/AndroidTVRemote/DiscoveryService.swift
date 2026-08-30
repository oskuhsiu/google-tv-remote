import Foundation

/// Explicit foundation placeholder. Bonjour discovery is wired in the transport slice.
@MainActor
final class UnavailableDiscoveryService: DiscoveryControlling {
    var onCandidatesChanged: (([TvCandidate]) -> Void)?

    func start() {
        onCandidatesChanged?([])
    }

    func stop() {}
}

/// Explicit foundation placeholder. It never reports a connection or sends a command.
@MainActor
final class UnavailableRemoteSession: RemoteSessionControlling {
    var onEvent: ((RemoteSessionEvent) -> Void)?
    func connect(to record: LastTvRecord) {}
    func disconnect() {}
    func send(command: RemoteCommand, action: RemoteKeyAction) {}
}
