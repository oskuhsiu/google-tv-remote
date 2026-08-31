import Foundation
import Network

@MainActor
final class BonjourDiscoveryService: DiscoveryControlling {
    var onCandidatesChanged: (([TvCandidate]) -> Void)?
    var onErrorChanged: ((RemoteError?) -> Void)?

    private static let serviceType = "_androidtvremote2._tcp"
    private static let serviceDomain = "local."

    private let queue = DispatchQueue(label: "remote.discovery")
    private var browser: NWBrowser?
    private var endpointsByKey: [String: NWEndpoint] = [:]
    private var candidatesByKey: [String: TvCandidate] = [:]
    private var resolversByKey: [String: NWConnection] = [:]
    private var lastPublishedCandidates: [TvCandidate]?
    private var generation = 0

    func start() {
        stop()
        let generation = generation
        lastPublishedCandidates = nil
        onErrorChanged?(nil)
        publishCandidates()

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: Self.serviceDomain),
            using: .tcp
        )
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.map(\.endpoint)
            Task { @MainActor [weak self] in
                self?.apply(endpoints: endpoints, generation: generation)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                switch state {
                case .ready:
                    self.onErrorChanged?(nil)
                case .waiting:
                    self.onErrorChanged?(.networkUnreachable)
                case .failed:
                    self.onErrorChanged?(.networkUnreachable)
                    self.cancelActiveNetworkWork()
                    self.endpointsByKey.removeAll()
                    self.candidatesByKey.removeAll()
                    self.publishCandidates()
                case .setup, .cancelled:
                    break
                @unknown default:
                    self.onErrorChanged?(.unknown)
                }
            }
        }
        browser.start(queue: queue)
    }

    func stop() {
        generation &+= 1
        cancelActiveNetworkWork()
        endpointsByKey.removeAll()
        candidatesByKey.removeAll()
        lastPublishedCandidates = nil
    }

    private func apply(endpoints: [NWEndpoint], generation: Int) {
        guard self.generation == generation else { return }

        let currentEndpoints = Dictionary(
            endpoints.compactMap { endpoint in
                locatorKey(for: endpoint).map { ($0, endpoint) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let removedKeys = Set(endpointsByKey.keys).subtracting(currentEndpoints.keys)
        for key in removedKeys {
            cancelResolver(for: key)
            candidatesByKey.removeValue(forKey: key)
        }

        for (key, endpoint) in currentEndpoints {
            let endpointChanged = endpointsByKey[key] != endpoint
            if endpointChanged {
                cancelResolver(for: key)
                candidatesByKey.removeValue(forKey: key)
            }
            if candidatesByKey[key] == nil, resolversByKey[key] == nil {
                resolve(endpoint: endpoint, key: key, generation: generation)
            }
        }

        endpointsByKey = currentEndpoints
        publishCandidates()
    }

    private func resolve(endpoint: NWEndpoint, key: String, generation: Int) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolversByKey[key] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                self.handleResolverState(
                    state,
                    connection: connection,
                    endpoint: endpoint,
                    key: key,
                    generation: generation
                )
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { [weak self, weak connection] in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection,
                      self.generation == generation,
                      self.resolversByKey[key] === connection else {
                    return
                }
                self.cancelResolver(for: key)
            }
        }
    }

    private func handleResolverState(
        _ state: NWConnection.State,
        connection: NWConnection,
        endpoint: NWEndpoint,
        key: String,
        generation: Int
    ) {
        guard self.generation == generation,
              resolversByKey[key] === connection,
              endpointsByKey[key] == endpoint else {
            connection.cancel()
            return
        }

        switch state {
        case .ready:
            if let host = resolvedHost(from: connection),
               let service = serviceDetails(from: endpoint) {
                candidatesByKey[key] = TvCandidate(
                    locatorKey: key,
                    name: service.name,
                    host: host,
                    source: .discovery
                )
            }
            cancelResolver(for: key)
            publishCandidates()
        case .failed, .cancelled:
            cancelResolver(for: key)
        case .setup, .waiting, .preparing:
            break
        @unknown default:
            cancelResolver(for: key)
        }
    }

    private func resolvedHost(from connection: NWConnection) -> String? {
        guard let endpoint = connection.currentPath?.remoteEndpoint,
              case .hostPort(let host, _) = endpoint else {
            return nil
        }
        return String(describing: host)
    }

    private func locatorKey(for endpoint: NWEndpoint) -> String? {
        guard let service = serviceDetails(from: endpoint) else { return nil }
        return "\(service.domain)|\(service.type)|\(service.name)"
    }

    private func serviceDetails(
        from endpoint: NWEndpoint
    ) -> (name: String, type: String, domain: String)? {
        guard case .service(let name, let type, let domain, _) = endpoint else {
            return nil
        }
        return (name, type, domain)
    }

    private func publishCandidates() {
        let candidates = candidatesByKey.values.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            return nameOrder == .orderedSame
                ? $0.locatorKey < $1.locatorKey
                : nameOrder == .orderedAscending
        }
        guard candidates != lastPublishedCandidates else { return }
        lastPublishedCandidates = candidates
        onCandidatesChanged?(candidates)
    }

    private func cancelActiveNetworkWork() {
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        for key in Array(resolversByKey.keys) {
            cancelResolver(for: key)
        }
    }

    private func cancelResolver(for key: String) {
        guard let connection = resolversByKey.removeValue(forKey: key) else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}

/// Preview-only placeholder that always reports an empty discovery result.
@MainActor
final class UnavailableDiscoveryService: DiscoveryControlling {
    var onCandidatesChanged: (([TvCandidate]) -> Void)?
    var onErrorChanged: ((RemoteError?) -> Void)?

    func start() {
        onCandidatesChanged?([])
    }

    func stop() {}
}

/// Explicit foundation placeholder. It never reports a connection or sends a command.
@MainActor
final class UnavailableRemoteSession: RemoteSessionControlling {
    var onEvent: ((RemoteSessionEvent) -> Void)?
    var onVoiceStateChanged: ((VoiceState) -> Void)?
    var onVoiceError: ((RemoteError) -> Void)?
    func startPairing(with device: RemoteDevice) {}
    func submitPairingCode(_ code: String) {}
    func connect(to record: LastTvRecord) {}
    func disconnect() {}
    func send(command: RemoteCommand, action: RemoteKeyAction) {}
    func startVoice() {}
    func stopVoice() {}
}
