import Foundation
import XCTest
@testable import AndroidTVRemote

final class LastTvStoreTests: XCTestCase {
    func testLegacyRecordWithoutSourceOrConnectionDateRetainsPairing() throws {
        var object = try encodedRecord()
        object.removeValue(forKey: "source")
        object.removeValue(forKey: "lastConnectedAt")

        let record = try JSONDecoder().decode(
            LastTvRecord.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(record.hasSameTrust(as: savedTV))
        XCTAssertTrue(record.isComplete)
        XCTAssertEqual(record.source, .manual)
        XCTAssertEqual(record.lastConnectedAt, .distantPast)
    }

    func testSavedPairingLoadsDespiteObsoleteWakeMetadata() throws {
        let obsoleteMetadata: [Any] = [
            ["macAddress": "A4:77:33:12:AB:CD", "source": "manual", "capability": "unverified"],
            ["macAddress": "00:00:00:00:00:00", "source": "manual", "capability": "verified"],
            ["macAddress": "A4:77:33:12:AB:CD", "source": "future-source", "capability": "future-status"],
            "not-an-object",
            NSNull()
        ]

        try withStore { defaults, store in
            for metadata in obsoleteMetadata {
                var object = try encodedRecord()
                object["networkWake"] = metadata
                defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "lastTvRecord")

                let record = try XCTUnwrap(store.load())
                XCTAssertEqual(record, savedTV)
                XCTAssertTrue(record.isComplete)
            }
        }
    }

    func testSavingOldRecordDropsWakeMetadataAndRetainsPairing() throws {
        try withStore { defaults, store in
            var object = try encodedRecord()
            object["networkWake"] = [
                "macAddress": "A4:77:33:12:AB:CD", "source": "manual", "capability": "verified"
            ]
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "lastTvRecord")

            let record = try XCTUnwrap(store.load())
            try store.save(record)

            let data = try XCTUnwrap(defaults.data(forKey: "lastTvRecord"))
            let savedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(savedObject["networkWake"])
            XCTAssertEqual(try store.load(), savedTV)
        }
    }

    func testHostRecoveryRetainsPairingAndDeviceMetadata() {
        let connectedAt = Date(timeIntervalSince1970: 2_000)
        let updated = savedTV.replacingHost("192.0.2.30", connectedAt: connectedAt)

        XCTAssertTrue(updated.hasSameTrust(as: savedTV))
        XCTAssertEqual(updated.lastHost, "192.0.2.30")
        XCTAssertEqual(updated.lastConnectedAt, connectedAt)
        XCTAssertEqual(updated.name, savedTV.name)
        XCTAssertEqual(updated.bonjourLocator, savedTV.bonjourLocator)
        XCTAssertEqual(updated.source, savedTV.source)
    }

    private let savedTV = LastTvRecord(
        persistentDeviceID: "tv", name: "Living Room TV", clientIdentityFingerprint: "client",
        pairingPeerFingerprint: "pairing", remotePeerFingerprint: "tv", lastHost: "192.0.2.10",
        bonjourLocator: BonjourLocator(domain: "local.", type: "_androidtvremote2._tcp", name: "Living Room"),
        source: .discovery, lastConnectedAt: Date(timeIntervalSince1970: 1_000)
    )

    private func encodedRecord() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(savedTV)) as? [String: Any])
    }

    private func withStore(_ check: (UserDefaults, LastTvStore) throws -> Void) throws {
        let suite = "LastTvStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(defaults, LastTvStore(defaults: defaults))
    }
}
