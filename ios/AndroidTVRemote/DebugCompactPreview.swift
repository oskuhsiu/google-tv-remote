#if DEBUG
import Foundation

enum DebugCompactPreview {
    static let record = LastTvRecord(
        persistentDeviceID: "preview-tv-fingerprint",
        name: "Living Room TV",
        clientIdentityFingerprint: "preview-client-fingerprint",
        pairingPeerFingerprint: "preview-pairing-fingerprint",
        remotePeerFingerprint: "preview-tv-fingerprint",
        lastHost: "192.0.2.10",
        bonjourLocator: nil,
        source: .manual,
        lastConnectedAt: .now
    )

    @MainActor
    final class Session: RemoteSessionControlling {
        var onEvent: ((RemoteSessionEvent) -> Void)?
        var onVoiceStateChanged: ((VoiceState) -> Void)?
        var onVoiceError: ((RemoteError) -> Void)?

        func connect(to record: LastTvRecord) {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.onEvent?(.connected(record.device))
            }
        }

        func disconnect() {}
        func send(command: RemoteCommand, action: RemoteKeyAction) {}
        func startVoice() {}
        func stopVoice() {}
    }

    @MainActor
    final class Identity: ClientIdentityValidating {
        func status(matching fingerprint: String) throws -> ClientIdentityStatus {
            fingerprint == record.clientIdentityFingerprint ? .matches : .mismatch
        }

        func deleteIdentity() throws {}
    }

    final class Store: LastTvStoring {
        private var record: LastTvRecord?

        init(record: LastTvRecord) {
            self.record = record
        }

        func load() throws -> LastTvRecord? { record }
        func save(_ record: LastTvRecord) throws { self.record = record }
        func clear() { record = nil }
    }
}
#endif
