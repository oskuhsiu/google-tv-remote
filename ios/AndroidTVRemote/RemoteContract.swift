import Foundation

enum AppRoute: Equatable, Sendable {
    case fullRemote
    case compactRemote

    static let compactURL = URL(string: "androidtvremote://compact")!

    init?(url: URL) {
        guard url.scheme?.caseInsensitiveCompare("androidtvremote") == .orderedSame,
              url.host?.caseInsensitiveCompare("compact") == .orderedSame else {
            return nil
        }
        self = .compactRemote
    }
}

enum RemoteCommand: String, CaseIterable, Codable, Sendable {
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case menu
    case power
    case volumeUp
    case volumeDown
    case mute

    var androidKeyCode: Int {
        switch self {
        case .up: 19
        case .down: 20
        case .left: 21
        case .right: 22
        case .select: 23
        case .back: 4
        case .home: 3
        case .menu: 82
        case .power: 26
        case .volumeUp: 24
        case .volumeDown: 25
        case .mute: 164
        }
    }

    func supports(_ action: RemoteKeyAction) -> Bool {
        action == .short || self == .select
    }
}

enum RemoteKeyAction: Equatable, Sendable {
    case short
    case startLong
    case endLong
}

enum RemotePressBehavior: Equatable, Sendable {
    case single
    case longPress
    case repeatWhileHeld
}

enum RemotePressPolicy {
    static let longPressThreshold: TimeInterval = 0.4
    static let repeatDelay: TimeInterval = 0.4
    static let repeatInterval: TimeInterval = 0.1

    static func behavior(for command: RemoteCommand) -> RemotePressBehavior {
        switch command {
        case .select:
            return .longPress
        case .up, .down, .left, .right, .volumeUp, .volumeDown:
            return .repeatWhileHeld
        case .back, .home, .menu, .power, .mute:
            return .single
        }
    }
}

enum TvSource: String, Codable, Sendable {
    case discovery
    case manual
}

struct BonjourLocator: Codable, Equatable, Sendable {
    let domain: String
    let type: String
    let name: String
}

struct TvCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { locatorKey }

    let locatorKey: String
    let name: String
    let host: String
    let source: TvSource
}

struct RemoteDevice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let host: String
    let locator: BonjourLocator?
    let source: TvSource

    init(
        id: String,
        name: String,
        host: String,
        locator: BonjourLocator?,
        source: TvSource = .manual
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.locator = locator
        self.source = source
    }
}

struct LastTvRecord: Codable, Equatable, Sendable {
    let persistentDeviceID: String
    let name: String
    let clientIdentityFingerprint: String
    let pairingPeerFingerprint: String
    let remotePeerFingerprint: String
    let lastHost: String
    let bonjourLocator: BonjourLocator?
    let source: TvSource
    let lastConnectedAt: Date

    init(
        persistentDeviceID: String,
        name: String,
        clientIdentityFingerprint: String,
        pairingPeerFingerprint: String,
        remotePeerFingerprint: String,
        lastHost: String,
        bonjourLocator: BonjourLocator?,
        source: TvSource = .manual,
        lastConnectedAt: Date = .distantPast
    ) {
        self.persistentDeviceID = persistentDeviceID
        self.name = name
        self.clientIdentityFingerprint = clientIdentityFingerprint
        self.pairingPeerFingerprint = pairingPeerFingerprint
        self.remotePeerFingerprint = remotePeerFingerprint
        self.lastHost = lastHost
        self.bonjourLocator = bonjourLocator
        self.source = source
        self.lastConnectedAt = lastConnectedAt
    }

    var isComplete: Bool {
        [persistentDeviceID, name, clientIdentityFingerprint, pairingPeerFingerprint,
         remotePeerFingerprint, lastHost].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && persistentDeviceID == remotePeerFingerprint
    }

    var device: RemoteDevice {
        RemoteDevice(
            id: persistentDeviceID,
            name: name,
            host: lastHost,
            locator: bonjourLocator,
            source: source
        )
    }
}

enum RemoteError: String, CaseIterable, Error, Sendable {
    case networkUnreachable = "NETWORK_UNREACHABLE"
    case tvNotFound = "TV_NOT_FOUND"
    case pairingRequired = "PAIRING_REQUIRED"
    case pairingCodeInvalid = "PAIRING_CODE_INVALID"
    case pairingRejected = "PAIRING_REJECTED"
    case pairingTimeout = "PAIRING_TIMEOUT"
    case trustChanged = "TRUST_CHANGED"
    case connectionLost = "CONNECTION_LOST"
    case voicePermissionDenied = "VOICE_PERMISSION_DENIED"
    case voiceSessionFailed = "VOICE_SESSION_FAILED"
    case textInputFailed = "TEXT_INPUT_FAILED"
    case unknown = "UNKNOWN"
}

enum RemoteState: Equatable, Sendable {
    case idle
    case discovering([TvCandidate])
    case connecting(RemoteDevice)
    case needsPairing(RemoteDevice)
    case pairing(RemoteDevice)
    case connected(RemoteDevice)
    case reconnecting(RemoteDevice, attempt: Int)
    case disconnected(RemoteDevice?)
    case failed(RemoteDevice?, reason: RemoteError, recoverable: Bool)
}

enum RemoteSessionEvent: Equatable, Sendable {
    case connected(RemoteDevice)
    case failed(RemoteDevice?, reason: RemoteError, recoverable: Bool)
}

enum ForegroundAction: Equatable {
    case none
    case connectRemembered
    case startDiscovery
}

enum ForegroundPolicy {
    static func action(alreadyActive: Bool, hasValidPairing: Bool) -> ForegroundAction {
        guard !alreadyActive else { return .none }
        return hasValidPairing ? .connectRemembered : .startDiscovery
    }

    static func allowsAutomaticDiscovery(isActive: Bool, hasValidPairing: Bool) -> Bool {
        isActive && !hasValidPairing
    }
}

enum BackgroundSessionAction: Equatable, Sendable {
    case disconnect
    case retainConnectedSession
}

enum BackgroundSessionPolicy {
    static func action(
        keepReadyEnabled: Bool,
        keepAliveAvailable: Bool,
        hasValidPairing: Bool,
        isConnected: Bool,
        disconnectedByUser: Bool
    ) -> BackgroundSessionAction {
        guard keepReadyEnabled,
              keepAliveAvailable,
              hasValidPairing,
              isConnected,
              !disconnectedByUser else {
            return .disconnect
        }
        return .retainConnectedSession
    }
}

enum KeepAliveStatus: Equatable, Sendable {
    case off
    case starting
    case ready
    case interrupted
}

enum ReconnectPolicy {
    static let delays: [TimeInterval] = [1, 2, 4]
}

enum PairingCodeValidator {
    static func isValid(_ code: String) -> Bool {
        normalized(code) != nil
    }

    static func normalized(_ code: String) -> String? {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.utf8.count == 6,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...70).contains(byte)
              }) else {
            return nil
        }
        return value
    }
}

@MainActor
protocol DiscoveryControlling: AnyObject {
    var onCandidatesChanged: (([TvCandidate]) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
protocol RemoteSessionControlling: AnyObject {
    var onEvent: ((RemoteSessionEvent) -> Void)? { get set }
    func connect(to record: LastTvRecord)
    func disconnect()
    func send(command: RemoteCommand, action: RemoteKeyAction)
}

@MainActor
protocol BackgroundKeepAliveControlling: AnyObject {
    var isAvailable: Bool { get }
    var status: KeepAliveStatus { get }
    var onStatusChanged: ((KeepAliveStatus) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
protocol ClientIdentityValidating: AnyObject {
    func status(matching fingerprint: String) throws -> ClientIdentityStatus
    func deleteIdentity() throws
}

enum ClientIdentityStatus: Equatable {
    case matches
    case missing
    case mismatch
}

extension IdentityStore: ClientIdentityValidating {}

protocol LastTvStoring: AnyObject {
    func load() throws -> LastTvRecord?
    func save(_ record: LastTvRecord) throws
    func clear()
}
