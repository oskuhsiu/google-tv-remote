import Foundation
import XCTest
@testable import AndroidTVRemote

final class WolPacketTests: XCTestCase {
    func testNormalizesColonDashAndPlainHex() {
        for input in ["a4:77:33:12:ab:cd", "A4-77-33-12-AB-CD", " a4773312abcd\n"] {
            XCTAssertEqual(WolPacket.normalizedMAC(input), "A4:77:33:12:AB:CD")
        }
    }

    func testRejectsMalformedAndUnusableAddresses() {
        for input in ["", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:00:5E:00:00:01",
                      "A4:77-33:12:AB:CD", "A4:77:33:12:AB", "A4:77:33:12:AB:CG",
                      "A4:77:33:12:AB:CD:", "A4 77 33 12 AB CD"] {
            XCTAssertNil(WolPacket.normalizedMAC(input), input)
            XCTAssertNil(WolPacket.make(macAddress: input), input)
        }
        // Locally administered unicast MACs are legitimate device addresses.
        XCTAssertNotNil(WolPacket.normalizedMAC("02:11:22:33:44:55"))
    }

    func testExactMagicPacketContainsSixFFBytesAndSixteenMACCopies() throws {
        let packet = try XCTUnwrap(WolPacket.make(macAddress: "A4:77:33:12:AB:CD"))
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), Array(repeating: 0xFF, count: 6))
        let mac: [UInt8] = [0xA4, 0x77, 0x33, 0x12, 0xAB, 0xCD]
        for index in 0..<16 {
            XCTAssertEqual(Array(packet[(6 + index * 6)..<(12 + index * 6)]), mac)
        }
    }
}

final class NetworkWakeStorageTests: XCTestCase {
    func testLegacyRecordWithoutWakeFieldRetainsPairing() throws {
        let data = try JSONEncoder().encode(wakeTestRecord)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "networkWake")
        let record = try JSONDecoder().decode(LastTvRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(record, wakeTestRecord)
        XCTAssertNil(record.networkWake)
        XCTAssertTrue(record.isComplete)
    }

    func testMalformedOptionalWakeMetadataDoesNotDiscardPairing() throws {
        let data = try JSONEncoder().encode(wakeTestRecord)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let malformed: [Any] = [
            "not-an-object",
            ["macAddress": "00:00:00:00:00:00", "source": "manual", "capability": "verified"],
            ["macAddress": "A4:77:33:12:AB:CD", "source": "future-source", "capability": "verified"],
            ["macAddress": "A4:77:33:12:AB:CD", "source": "manual", "capability": "future-status"]
        ]
        for metadata in malformed {
            var object = original
            object["networkWake"] = metadata
            let record = try JSONDecoder().decode(LastTvRecord.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertTrue(record.hasSameTrust(as: wakeTestRecord))
            XCTAssertTrue(record.isComplete)
            XCTAssertNil(record.networkWake)
        }
    }

    func testWakeMetadataRoundTripsThroughRealStore() throws {
        let suite = "NetworkWakeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LastTvStore(defaults: defaults)
        var record = wakeTestRecord
        record.networkWake = NetworkWakeSettings(macAddress: "a4-77-33-12-ab-cd")
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
        XCTAssertEqual(try store.load()?.networkWake?.capability, .unverified)
        XCTAssertEqual(try store.load()?.networkWake?.source, .manual)
    }

    func testDecodedWakeMACIsNormalized() throws {
        let data = Data(#"{"macAddress":"a4773312abcd","source":"manual","capability":"unverified"}"#.utf8)
        let settings = try JSONDecoder().decode(NetworkWakeSettings.self, from: data)
        XCTAssertEqual(settings.macAddress, "A4:77:33:12:AB:CD")
        XCTAssertEqual(settings.capability, .unverified)
    }
}

@MainActor
final class NetworkWakeModelTests: XCTestCase {
    func testSaveEditClearRetainsTrustAndPersists() throws {
        let fixture = WakeModelFixture()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("a4773312abcd"))
        XCTAssertEqual(fixture.model.rememberedRecord?.networkWake?.macAddress, "A4:77:33:12:AB:CD")
        XCTAssertEqual(fixture.model.rememberedRecord?.networkWake?.capability, .unverified)
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("02-11-22-33-44-55"))
        XCTAssertEqual(try fixture.store.load(), fixture.model.rememberedRecord)
        XCTAssertTrue(try XCTUnwrap(fixture.store.load()).hasSameTrust(as: wakeTestRecord))
        XCTAssertTrue(fixture.model.clearNetworkWakeMAC())
        XCTAssertNil(fixture.model.rememberedRecord?.networkWake)
        XCTAssertEqual(try fixture.store.load(), wakeTestRecord)
        XCTAssertEqual(fixture.identity.deleteCount, 0)
    }

    func testInvalidInputAndStorageFailurePreservePriorSettings() {
        let fixture = WakeModelFixture()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        let original = fixture.model.rememberedRecord
        XCTAssertFalse(fixture.model.saveNetworkWakeMAC("FF:FF:FF:FF:FF:FF"))
        XCTAssertEqual(fixture.model.rememberedRecord, original)
        fixture.store.failSave = true
        XCTAssertFalse(fixture.model.saveNetworkWakeMAC("02:11:22:33:44:55"))
        XCTAssertEqual(fixture.model.rememberedRecord, original)
        XCTAssertFalse(fixture.model.clearNetworkWakeMAC())
        XCTAssertEqual(fixture.model.rememberedRecord, original)
    }

    func testPacketTestDoesNotReconnectPairOrVerifyCapability() async {
        let sender = RecordingWolSender()
        let fixture = WakeModelFixture(sender: sender)
        fixture.model.enterForeground()
        fixture.model.disconnect()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        let task = fixture.model.testNetworkWake()
        await task?.value
        let addresses = await sender.addresses
        XCTAssertEqual(addresses, ["A4:77:33:12:AB:CD"])
        XCTAssertEqual(fixture.model.state, .disconnected(wakeTestRecord.device))
        XCTAssertEqual(fixture.session.connectedRecords.count, 1)
        XCTAssertEqual(fixture.session.pairingCount, 0)
        XCTAssertEqual(fixture.model.rememberedRecord?.networkWake?.capability, .unverified)
        XCTAssertFalse(fixture.model.isTestingNetworkWake)
        XCTAssertEqual(fixture.model.networkWakeMessage, NSLocalizedString("Wake packet sent. This does not confirm that the TV woke.", comment: ""))
    }

    func testForegroundDirectConnectNeverSendsCandidateOrVerifiedWake() async {
        for capability in [NetworkWakeSettings.Capability.unverified, .verified] {
            var record = wakeTestRecord
            record.networkWake = NetworkWakeSettings(macAddress: "A4:77:33:12:AB:CD", capability: capability)
            let sender = RecordingWolSender()
            let fixture = WakeModelFixture(record: record, sender: sender)
            fixture.model.enterForeground()
            let addresses = await sender.addresses
            XCTAssertTrue(addresses.isEmpty)
            XCTAssertEqual(fixture.session.connectedRecords, [record])
        }
    }

    func testSendFailureRetainsCandidateAndSessionState() async {
        let sender = RecordingWolSender(error: .sendFailed)
        let fixture = WakeModelFixture(sender: sender)
        fixture.model.enterForeground()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        let originalState = fixture.model.state
        await fixture.model.testNetworkWake()?.value
        XCTAssertEqual(fixture.model.state, originalState)
        XCTAssertEqual(fixture.model.rememberedRecord?.networkWake?.capability, .unverified)
        XCTAssertFalse(fixture.model.isTestingNetworkWake)
        XCTAssertEqual(fixture.model.networkWakeMessage, NSLocalizedString("Could not send the wake packet. Check Local Network permission and your Wi-Fi connection, then try again.", comment: ""))
    }

    func testNoSavedMACCannotSend() async {
        let sender = RecordingWolSender()
        let fixture = WakeModelFixture(sender: sender)
        fixture.model.enterForeground()
        XCTAssertNil(fixture.model.testNetworkWake())
        let addresses = await sender.addresses
        XCTAssertTrue(addresses.isEmpty)
    }

    func testEditedMACSuppressesOldTestCompletion() async {
        let sender = SuspendedWolSender()
        let fixture = WakeModelFixture(sender: sender)
        fixture.model.enterForeground()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        let task = fixture.model.testNetworkWake()
        await sender.waitUntilStarted()
        XCTAssertTrue(fixture.model.isTestingNetworkWake)
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("02:11:22:33:44:55"))
        let editMessage = fixture.model.networkWakeMessage
        await sender.release()
        await task?.value
        XCTAssertFalse(fixture.model.isTestingNetworkWake)
        XCTAssertEqual(fixture.model.networkWakeMessage, editMessage)
        XCTAssertEqual(fixture.model.rememberedRecord?.networkWake?.macAddress, "02:11:22:33:44:55")
    }

    func testSameTrustedTVSessionCompletionPreservesLatestEditAndClear() {
        let fixture = WakeModelFixture()
        fixture.model.enterForeground()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        fixture.session.onEvent?(.pairingCompleted(wakeTestRecord))
        XCTAssertEqual(fixture.model.rememberedRecord?.networkWake?.macAddress, "A4:77:33:12:AB:CD")
        let staleRecord = fixture.model.rememberedRecord!
        XCTAssertTrue(fixture.model.clearNetworkWakeMAC())
        fixture.session.onEvent?(.pairingCompleted(staleRecord))
        XCTAssertNil(fixture.model.rememberedRecord?.networkWake)
    }

    func testClientCertificateRepairKeepsLatestMACAndTrustedTVMetadata() {
        let fixture = WakeModelFixture()
        fixture.model.enterForeground()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        let original = fixture.model.rememberedRecord!
        let repaired = LastTvRecord(
            persistentDeviceID: original.persistentDeviceID, name: original.name,
            clientIdentityFingerprint: "repaired-client-certificate",
            pairingPeerFingerprint: original.pairingPeerFingerprint,
            remotePeerFingerprint: original.remotePeerFingerprint, lastHost: "192.0.2.30",
            bonjourLocator: original.bonjourLocator, source: original.source,
            networkWake: nil
        )
        fixture.session.onEvent?(.pairingCompleted(repaired))
        XCTAssertEqual(fixture.model.rememberedRecord?.networkWake?.macAddress, "A4:77:33:12:AB:CD")
        XCTAssertEqual(fixture.model.rememberedRecord?.clientIdentityFingerprint, repaired.clientIdentityFingerprint)
        XCTAssertEqual(fixture.model.rememberedRecord?.name, original.name)
        XCTAssertEqual(fixture.model.rememberedRecord?.bonjourLocator, original.bonjourLocator)
        XCTAssertEqual(fixture.model.rememberedRecord?.source, original.source)
    }

    func testDifferentTrustedTVDoesNotInheritWakeSettings() {
        let fixture = WakeModelFixture()
        fixture.model.enterForeground()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        let differentTV = LastTvRecord(
            persistentDeviceID: "new-tv", name: "Bedroom TV", clientIdentityFingerprint: "client",
            pairingPeerFingerprint: "new-pairing", remotePeerFingerprint: "new-tv", lastHost: "192.0.2.20",
            bonjourLocator: nil
        )
        fixture.session.onEvent?(.pairingCompleted(differentTV))
        XCTAssertNil(fixture.model.rememberedRecord?.networkWake)
        XCTAssertEqual(fixture.model.rememberedRecord, differentTV)
    }

    func testEditingMACDuringScheduledReconnectUsesLatestRecord() async {
        let sleeper = WakeRetryGate()
        let fixture = WakeModelFixture(retrySleep: sleeper.sleep)
        fixture.model.enterForeground()
        fixture.session.onEvent?(.failed(wakeTestRecord.device, reason: .connectionLost, recoverable: true))
        await sleeper.waitUntilSleeping()
        XCTAssertTrue(fixture.model.saveNetworkWakeMAC("A4:77:33:12:AB:CD"))
        let connected = expectation(description: "Reconnect uses latest metadata")
        fixture.session.onConnect = { _ in connected.fulfill() }
        sleeper.release()
        await fulfillment(of: [connected], timeout: 1)
        XCTAssertEqual(fixture.session.connectedRecords.last, fixture.model.rememberedRecord)
        XCTAssertEqual(fixture.model.state, .reconnecting(wakeTestRecord.device, attempt: 1))
    }
}

private let wakeTestRecord = LastTvRecord(
    persistentDeviceID: "tv", name: "Living Room TV", clientIdentityFingerprint: "client",
    pairingPeerFingerprint: "pairing", remotePeerFingerprint: "tv", lastHost: "192.0.2.10",
    bonjourLocator: nil
)

@MainActor
private final class WakeModelFixture {
    let session = WakeRecordingSession()
    let identity = WakeIdentity()
    let store: WakeMemoryStore
    let model: AppModel

    init(
        record: LastTvRecord = wakeTestRecord,
        sender: WolSending = RecordingWolSender(),
        retrySleep: @escaping (TimeInterval) async throws -> Void = { _ in }
    ) {
        store = WakeMemoryStore(record: record)
        model = AppModel(
            discovery: UnavailableDiscoveryService(), session: session, identity: identity,
            store: store, wolSender: sender, retrySleep: retrySleep
        )
    }
}

@MainActor
private final class WakeIdentity: ClientIdentityValidating {
    var deleteCount = 0
    func status(matching fingerprint: String) throws -> ClientIdentityStatus { .matches }
    func deleteIdentity() throws { deleteCount += 1 }
}

private final class WakeMemoryStore: LastTvStoring {
    private var record: LastTvRecord?
    var failSave = false
    init(record: LastTvRecord) { self.record = record }
    func load() throws -> LastTvRecord? { record }
    func save(_ record: LastTvRecord) throws {
        if failSave { throw WolSendError.sendFailed }
        self.record = record
    }
    func clear() { record = nil }
}

@MainActor
private final class WakeRecordingSession: RemoteSessionControlling {
    var onEvent: ((RemoteSessionEvent) -> Void)?
    var onVoiceStateChanged: ((VoiceState) -> Void)?
    var onVoiceError: ((RemoteError) -> Void)?
    var onConnect: ((LastTvRecord) -> Void)?
    var connectedRecords: [LastTvRecord] = []
    var pairingCount = 0
    func startPairing(with device: RemoteDevice) { pairingCount += 1 }
    func submitPairingCode(_ code: String) {}
    func connect(to record: LastTvRecord) {
        connectedRecords.append(record)
        onConnect?(record)
    }
    func disconnect() {}
    func send(command: RemoteCommand, action: RemoteKeyAction) {}
    func startVoice() {}
    func stopVoice() {}
}

private actor RecordingWolSender: WolSending {
    var addresses: [String] = []
    let error: WolSendError?
    init(error: WolSendError? = nil) { self.error = error }
    func send(macAddress: String) async throws {
        addresses.append(macAddress)
        if let error { throw error }
    }
}

private actor SuspendedWolSender: WolSending {
    private var started = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    func send(macAddress: String) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class WakeRetryGate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    func sleep(_ delay: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }
    func waitUntilSleeping() async {
        if continuation != nil { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
