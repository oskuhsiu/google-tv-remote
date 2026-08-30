import Foundation
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
        XCTAssertEqual(fixture.session.connectedRecords, [.valid])
    }

    func testUnpairedActiveStartsDiscovery() {
        let fixture = Fixture(record: nil)
        fixture.model.enterForeground()
        XCTAssertEqual(fixture.discovery.startCount, 1)
        XCTAssertTrue(fixture.session.connectedRecords.isEmpty)
        XCTAssertEqual(fixture.identity.deleteCount, 1)
    }

    func testDisconnectRetainsTupleAndSuppressesSameForegroundReconnect() throws {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()

        fixture.model.disconnect()
        fixture.model.enterForeground()

        XCTAssertEqual(fixture.session.connectedRecords.count, 1)
        XCTAssertEqual(try fixture.store.load(), .valid)
        XCTAssertEqual(fixture.discovery.startCount, 0)
    }

    func testExplicitConnectAfterDisconnectAcceptsConnectedEvent() {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()
        fixture.model.disconnect()

        fixture.model.connectRemembered()
        fixture.session.emit(.connected(LastTvRecord.valid.device))

        XCTAssertEqual(fixture.session.connectedRecords.count, 2)
        XCTAssertEqual(fixture.model.state, .connected(LastTvRecord.valid.device))
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
        XCTAssertTrue(fixture.session.connectedRecords.isEmpty)
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

    func testKeychainReadFailurePreservesRecordAndBlocksDiscovery() {
        let fixture = Fixture(record: .valid, identityFailure: TestFailure.keychain)

        fixture.model.enterForeground()

        XCTAssertEqual(fixture.model.rememberedRecord, .valid)
        XCTAssertEqual(fixture.store.clearCount, 0)
        XCTAssertEqual(fixture.discovery.startCount, 0)
        fixture.model.connectRemembered()
        XCTAssertTrue(fixture.session.connectedRecords.isEmpty)
        guard case .failed = fixture.model.state else {
            return XCTFail("Expected a fail-closed state")
        }
    }

    func testForgetFailurePreservesTupleAndDoesNotDiscover() throws {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()
        fixture.identity.deleteFailure = TestFailure.keychain

        fixture.model.forget()

        XCTAssertEqual(try fixture.store.load(), .valid)
        XCTAssertEqual(fixture.discovery.startCount, 0)
        guard case .failed = fixture.model.state else {
            return XCTFail("Expected a recoverable failure")
        }
    }

    func testDecodeFailureClearsTupleBeforeDiscovery() {
        let fixture = Fixture(record: .valid, storeFailure: TestFailure.decode)

        fixture.model.enterForeground()

        XCTAssertEqual(fixture.store.clearCount, 1)
        XCTAssertEqual(fixture.identity.deleteCount, 1)
        XCTAssertEqual(fixture.discovery.startCount, 1)
    }

    func testPairingRequiredTransitionsToNeedsPairing() {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()

        fixture.session.emit(
            .failed(LastTvRecord.valid.device, reason: .pairingRequired, recoverable: true)
        )

        XCTAssertEqual(fixture.model.state, .needsPairing(LastTvRecord.valid.device))
        XCTAssertEqual(fixture.discovery.startCount, 0)
    }

    func testConnectionLossRetriesAfterOneTwoFourSecondsThenFails() async {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()
        let failure = RemoteSessionEvent.failed(
            LastTvRecord.valid.device,
            reason: .connectionLost,
            recoverable: true
        )

        fixture.session.emit(failure)
        await settleTasks()
        XCTAssertEqual(fixture.model.state, .reconnecting(LastTvRecord.valid.device, attempt: 1))

        fixture.session.emit(failure)
        await settleTasks()
        XCTAssertEqual(fixture.model.state, .reconnecting(LastTvRecord.valid.device, attempt: 2))

        fixture.session.emit(failure)
        await settleTasks()
        XCTAssertEqual(fixture.model.state, .reconnecting(LastTvRecord.valid.device, attempt: 3))

        fixture.session.emit(failure)
        XCTAssertEqual(
            fixture.model.state,
            .failed(LastTvRecord.valid.device, reason: .connectionLost, recoverable: true)
        )
        XCTAssertEqual(fixture.retrySleeper.delays, [1, 2, 4])
        XCTAssertEqual(fixture.session.connectedRecords.count, 4)
    }

    func testNetworkRetryExhaustionPreservesNetworkError() async {
        let fixture = Fixture(record: .valid)
        fixture.model.enterForeground()
        let failure = RemoteSessionEvent.failed(
            LastTvRecord.valid.device,
            reason: .networkUnreachable,
            recoverable: true
        )

        for _ in 0..<3 {
            fixture.session.emit(failure)
            await settleTasks()
        }
        fixture.session.emit(failure)

        XCTAssertEqual(
            fixture.model.state,
            .failed(LastTvRecord.valid.device, reason: .networkUnreachable, recoverable: true)
        )
    }

    private func settleTasks() async {
        try? await Task.sleep(nanoseconds: 10_000_000)
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
    let identity: RecordingIdentity
    let store: MemoryStore
    let retrySleeper = RecordingSleeper()
    let model: AppModel

    init(
        record: LastTvRecord?,
        identityFailure: Error? = nil,
        storeFailure: Error? = nil
    ) {
        identity = RecordingIdentity(statusFailure: identityFailure)
        store = MemoryStore(record: record, loadFailure: storeFailure)
        model = AppModel(
            discovery: discovery,
            session: session,
            identity: identity,
            store: store,
            retrySleep: retrySleeper.sleep
        )
    }
}

@MainActor
private final class RecordingDiscovery: DiscoveryControlling {
    var onCandidatesChanged: (([TvCandidate]) -> Void)?
    var startCount = 0
    var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
private final class RecordingSession: RemoteSessionControlling {
    var onEvent: ((RemoteSessionEvent) -> Void)?
    var connectedRecords: [LastTvRecord] = []
    var disconnectCount = 0
    func connect(to record: LastTvRecord) { connectedRecords.append(record) }
    func disconnect() { disconnectCount += 1 }
    func send(command: RemoteCommand, action: RemoteKeyAction) {}
    func emit(_ event: RemoteSessionEvent) { onEvent?(event) }
}

@MainActor
private final class RecordingIdentity: ClientIdentityValidating {
    var deleteCount = 0
    var deleteFailure: Error?
    private let statusFailure: Error?

    init(statusFailure: Error?) {
        self.statusFailure = statusFailure
    }

    func status(matching fingerprint: String) throws -> ClientIdentityStatus {
        if let statusFailure { throw statusFailure }
        return fingerprint == "client-fingerprint" ? .matches : .mismatch
    }

    func deleteIdentity() throws {
        deleteCount += 1
        if let deleteFailure { throw deleteFailure }
    }
}

private enum TestFailure: Error {
    case keychain
    case decode
}

private final class MemoryStore: LastTvStoring {
    private var record: LastTvRecord?
    private let loadFailure: Error?
    var clearCount = 0
    init(record: LastTvRecord?, loadFailure: Error?) {
        self.record = record
        self.loadFailure = loadFailure
    }
    func load() throws -> LastTvRecord? {
        if let loadFailure { throw loadFailure }
        return record
    }
    func save(_ record: LastTvRecord) throws { self.record = record }
    func clear() { clearCount += 1; record = nil }
}

private final class RecordingSleeper {
    private(set) var delays: [TimeInterval] = []

    func sleep(_ delay: TimeInterval) async throws {
        delays.append(delay)
    }
}
