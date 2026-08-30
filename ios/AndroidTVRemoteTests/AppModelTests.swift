import XCTest
@testable import AndroidTVRemote

@MainActor
final class AppModelTests: XCTestCase {
    func testCommandsHaveExactCountAndMappingWithoutPlayPause() {
        XCTAssertEqual(RemoteCommand.allCases.count, 12)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: RemoteCommand.allCases.map { ($0, $0.androidKeyCode) }), [
            .up: 19, .down: 20, .left: 21, .right: 22, .select: 23,
            .back: 4, .home: 3, .menu: 82, .power: 26,
            .volumeUp: 24, .volumeDown: 25, .mute: 164
        ])
        XCTAssertFalse(RemoteCommand.allCases.map(\.rawValue).contains("playPause"))
    }

    func testReconnectDelaysAreOneTwoFourSeconds() {
        XCTAssertEqual(ReconnectPolicy.delays, [1, 2, 4])
    }

    func testPairingCodeRequiresSixHexCharacters() {
        XCTAssertTrue(PairingCodeValidator.isValid("A1b2F0"))
        XCTAssertEqual(PairingCodeValidator.normalized("  a1b2f0\n"), "A1B2F0")
        XCTAssertFalse(PairingCodeValidator.isValid("A1B2F"))
        XCTAssertFalse(PairingCodeValidator.isValid("A1B2G0"))
    }

    func testPressPoliciesMatchSharedTimingContract() {
        XCTAssertEqual(RemotePressPolicy.longPressThreshold, 0.4)
        XCTAssertEqual(RemotePressPolicy.repeatDelay, 0.4)
        XCTAssertEqual(RemotePressPolicy.repeatInterval, 0.1)
        XCTAssertEqual(RemotePressPolicy.behavior(for: .select), .longPress)
        XCTAssertEqual(RemotePressPolicy.behavior(for: .up), .repeatWhileHeld)
        XCTAssertEqual(RemotePressPolicy.behavior(for: .volumeDown), .repeatWhileHeld)
        XCTAssertEqual(RemotePressPolicy.behavior(for: .home), .single)
    }

    func testForegroundPolicySelectsPairedAndUnpairedPaths() {
        XCTAssertEqual(ForegroundPolicy.action(alreadyActive: false, hasValidPairing: true), .connectRemembered)
        XCTAssertEqual(ForegroundPolicy.action(alreadyActive: false, hasValidPairing: false), .startDiscovery)
        XCTAssertEqual(ForegroundPolicy.action(alreadyActive: true, hasValidPairing: true), .none)
    }

    func testPairedActiveConnectsWithoutScanningAndDuplicateActiveDoesNothing() {
        let fixture = Fixture(record: .valid)

        fixture.model.enterForeground()
        fixture.model.enterForeground()

        XCTAssertEqual(fixture.discovery.startCount, 0)
        XCTAssertEqual(fixture.discovery.stopCount, 1)
        XCTAssertEqual(fixture.session.connectedDevices, [LastTvRecord.valid.device])
    }

    func testUnpairedActiveStartsDiscovery() {
        let fixture = Fixture(record: nil)
        fixture.model.enterForeground()
        XCTAssertEqual(fixture.discovery.startCount, 1)
        XCTAssertTrue(fixture.session.connectedDevices.isEmpty)
    }

    func testDisconnectRetainsTupleAndSuppressesSameForegroundReconnect() throws {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()

        fixture.model.disconnect()
        fixture.model.enterForeground()

        XCTAssertEqual(fixture.session.connectedDevices.count, 1)
        XCTAssertEqual(try fixture.store.load(), .valid)
        XCTAssertEqual(fixture.discovery.startCount, 0)
    }

    func testForgetClearsTupleAndStartsDiscoveryWhenActive() throws {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()
        fixture.model.forget()

        XCTAssertNil(try fixture.store.load())
        XCTAssertEqual(fixture.identity.deleteCount, 1)
        XCTAssertEqual(fixture.discovery.startCount, 1)
    }

    func testInvalidTupleFailsClosed() {
        let invalid = LastTvRecord(
            persistentDeviceID: "tv", name: "TV", clientIdentityFingerprint: "client",
            pairingPeerFingerprint: "", remotePeerFingerprint: "remote", lastHost: "192.0.2.1",
            bonjourLocator: nil
        )
        let fixture = Fixture(record: invalid)

        XCTAssertNil(fixture.model.rememberedRecord)
        XCTAssertEqual(fixture.store.clearCount, 1)
        XCTAssertEqual(fixture.identity.deleteCount, 1)
        fixture.model.enterForeground()
        XCTAssertEqual(fixture.discovery.startCount, 1)
        XCTAssertTrue(fixture.session.connectedDevices.isEmpty)
    }

    func testDeviceIdentifierMustMatchRemotePeerFingerprint() {
        let invalid = LastTvRecord(
            persistentDeviceID: "different-peer", name: "TV",
            clientIdentityFingerprint: "client-fingerprint",
            pairingPeerFingerprint: "pairing-peer-fingerprint",
            remotePeerFingerprint: "remote-peer-fingerprint",
            lastHost: "192.0.2.1", bonjourLocator: nil
        )
        let fixture = Fixture(record: invalid)

        XCTAssertNil(fixture.model.rememberedRecord)
        XCTAssertEqual(fixture.store.clearCount, 1)
        XCTAssertEqual(fixture.identity.deleteCount, 1)
    }
}

private extension LastTvRecord {
    static let valid = LastTvRecord(
        persistentDeviceID: "remote-peer-fingerprint",
        name: "Living Room TV",
        clientIdentityFingerprint: "client-fingerprint",
        pairingPeerFingerprint: "pairing-peer-fingerprint",
        remotePeerFingerprint: "remote-peer-fingerprint",
        lastHost: "192.0.2.10",
        bonjourLocator: BonjourLocator(domain: "local.", type: "_androidtvremote2._tcp", name: "Living Room")
    )
}

@MainActor
private final class Fixture {
    let discovery = RecordingDiscovery()
    let session = RecordingSession()
    let identity = RecordingIdentity()
    let store: MemoryStore
    let model: AppModel

    init(record: LastTvRecord?) {
        store = MemoryStore(record: record)
        model = AppModel(discovery: discovery, session: session, identity: identity, store: store)
    }
}

@MainActor
private final class RecordingDiscovery: DiscoveryControlling {
    var onDevicesChanged: (([RemoteDevice]) -> Void)?
    var startCount = 0
    var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
private final class RecordingSession: RemoteSessionControlling {
    var onEvent: ((RemoteSessionEvent) -> Void)?
    var connectedDevices: [RemoteDevice] = []
    var disconnectCount = 0
    func connect(to device: RemoteDevice) { connectedDevices.append(device) }
    func disconnect() { disconnectCount += 1 }
    func send(command: RemoteCommand, action: RemoteKeyAction) {}
}

@MainActor
private final class RecordingIdentity: ClientIdentityValidating {
    var deleteCount = 0
    func hasMatchingIdentity(fingerprint: String) -> Bool { fingerprint == "client-fingerprint" }
    func deleteIdentity() { deleteCount += 1 }
}

private final class MemoryStore: LastTvStoring {
    private var record: LastTvRecord?
    var clearCount = 0
    init(record: LastTvRecord?) { self.record = record }
    func load() throws -> LastTvRecord? { record }
    func save(_ record: LastTvRecord) throws { self.record = record }
    func clear() { clearCount += 1; record = nil }
}
