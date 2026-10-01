import AndroidTVRemoteControl
import Foundation
import Network
import Security
import XCTest
@testable import AndroidTVRemote

final class IdentityRepairTests: XCTestCase {
    private func namespace() -> String { "identity-repair-test.\(UUID().uuidString)" }
    private func assertSamePrivateKey(_ original: ClientIdentity, _ repaired: ClientIdentity) throws {
        let challenge = Data("same-key repair test".utf8)
        var error: Unmanaged<CFError>?
        let signature = try XCTUnwrap(SecKeyCreateSignature(repaired.privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                          challenge as CFData, &error))
        XCTAssertTrue(SecKeyVerifySignature(original.publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                           challenge as CFData, signature, &error))
    }
    func testFreshCertificateCNIsUniqueAndPoloNameMatchesAcrossReload() throws {
        let name = namespace(), first = IdentityStore(namespace: name), second = IdentityStore(namespace: namespace())
        defer { try? first.deleteAll(); try? second.deleteAll() }
        let a = try first.loadOrCreate(), b = try second.loadOrCreate()
        XCTAssertTrue(IdentityStore.isUniqueName(a.clientName))
        XCTAssertNotEqual(a.clientName, b.clientName)
        XCTAssertEqual(SecCertificateCopySubjectSummary(a.certificate) as String?, a.clientName)
        let reload = try XCTUnwrap(IdentityStore(namespace: name).load())
        XCTAssertEqual(reload.clientName, a.clientName)
        XCTAssertEqual(reload.fingerprint, a.fingerprint)
    }
    func testLegacyUpgradeDoesNotModifyExistingCertificate() throws {
        let source = IdentityStore(namespace: namespace())
        defer { try? source.deleteAll() }
        let original = try source.createLegacyIdentityForTesting()
        let loaded = try source.loadOrCreate()
        XCTAssertEqual(loaded.fingerprint, original.fingerprint)
        XCTAssertEqual(SecCertificateCopySubjectSummary(loaded.certificate) as String?, "Android TV Remote")
    }
    func testRepairStagesSameKeyCertificateAndCancellationLeavesOriginal() throws {
        let source = IdentityStore(namespace: namespace())
        defer { try? source.deleteAll() }
        let original = try source.createLegacyIdentityForTesting(), draft = try source.identityForRepair()
        XCTAssertNotEqual(draft.fingerprint, original.fingerprint)
        XCTAssertEqual(SecCertificateCopySubjectSummary(draft.certificate) as String?, draft.clientName)
        XCTAssertTrue(IdentityStore.isUniqueName(draft.clientName))
        try assertSamePrivateKey(original, draft)
        let retained = try XCTUnwrap(source.load())
        XCTAssertEqual(retained.fingerprint, original.fingerprint)
        XCTAssertEqual(retained.clientName, original.clientName)
    }
    func testMetadataFailureRollsBackCertificateAndSuccessCommitsDraft() throws {
        let source = IdentityStore(namespace: namespace())
        defer { try? source.deleteAll() }
        let original = try source.createLegacyIdentityForTesting(), draft = try source.identityForRepair()
        enum Failure: Error { case save }
        XCTAssertThrowsError(try source.commitCertificate(draft) { throw Failure.save })
        let rolledBack = try XCTUnwrap(source.load())
        XCTAssertEqual(rolledBack.fingerprint, original.fingerprint)
        try assertSamePrivateKey(original, rolledBack)
        var saved = false
        try source.commitCertificate(draft) { saved = true }
        XCTAssertTrue(saved)
        let committed = try XCTUnwrap(source.load())
        XCTAssertEqual(committed.fingerprint, draft.fingerprint)
        XCTAssertEqual(committed.clientName, draft.clientName)
        try assertSamePrivateKey(original, committed)
    }
    func testAlreadyUniqueCertificateRepairDoesNotRotateCertificateOrKey() throws {
        let source = IdentityStore(namespace: namespace())
        defer { try? source.deleteAll() }
        let original = try source.loadOrCreate(), repaired = try source.identityForRepair()
        XCTAssertEqual(repaired.fingerprint, original.fingerprint)
        XCTAssertEqual(repaired.clientName, original.clientName)
        try assertSamePrivateKey(original, repaired)
    }
    func testKnownPairingTrustCaptureRejectsChangedCertificate() throws {
        let source = IdentityStore(namespace: namespace())
        defer { try? source.deleteAll() }
        let identity = try source.loadOrCreate()
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(identity.certificate, SecPolicyCreateBasicX509(), &trust), errSecSuccess)
        let accepted = FirstUseTrustCapture(expectedFingerprint: identity.fingerprint)
        XCTAssertTrue(accepted.evaluate(try XCTUnwrap(trust)))
        let changed = FirstUseTrustCapture(expectedFingerprint: String(repeating: "f", count: 64))
        XCTAssertFalse(changed.evaluate(try XCTUnwrap(trust)))
        XCTAssertTrue(changed.trustChanged)
        XCTAssertNil(changed.fingerprint)
    }
    func testAddressRecoveryRequiresConnectionStagePOSIXOrDNSFailure() {
        XCTAssertTrue(AdapterErrorPolicy.isAddressFailure(.connectionFailed(NWError.posix(.ECONNREFUSED))))
        XCTAssertTrue(AdapterErrorPolicy.isAddressFailure(.connectionWaitingError(NWError.posix(.ETIMEDOUT))))
        XCTAssertTrue(AdapterErrorPolicy.isAddressFailure(.connectionFailed(NWError.dns(-65538))))
        XCTAssertFalse(AdapterErrorPolicy.isAddressFailure(.connectionFailed(NWError.tls(errSSLProtocol))))
        XCTAssertFalse(AdapterErrorPolicy.isAddressFailure(.connectionWaitingError(NWError.tls(errSSLProtocol))))
        XCTAssertFalse(AdapterErrorPolicy.isAddressFailure(.receiveDataError(NWError.posix(.ECONNRESET))))
        XCTAssertFalse(AdapterErrorPolicy.isAddressFailure(.sendDataError(NWError.posix(.ECONNRESET))))
        XCTAssertFalse(AdapterErrorPolicy.isAddressFailure(.connectionFailed(NSError(domain: "local-validation", code: Int(ECONNREFUSED)))))
    }

    func testClientRejectionRejectsCertificateWordsWithoutTypedSSLStatus() {
        let device = RemoteDevice(id: "tv", name: "Test TV", host: "192.0.2.1", locator: nil)
        for message in ["Local validation failed: certificate_unknown", "bad_certificate_status_response", "bad certificate", "unknown_ca"] {
            let error = AndroidTVRemoteControlError.receiveDataError(NSError(domain: "local-validation", code: Int(errSSLPeerCertUnknown),
                userInfo: [NSLocalizedDescriptionKey: message]))
            XCTAssertFalse(AdapterErrorPolicy.isClientRejection(error))
            XCTAssertEqual(AdapterErrorPolicy.failure(error: error, for: .accepted("pin"), device: device),
                           .failed(device, reason: .networkUnreachable, recoverable: true))
        }
        let typed = AndroidTVRemoteControlError.receiveDataError(NSError(domain: NSOSStatusErrorDomain, code: Int(errSSLPeerCertUnknown)))
        XCTAssertTrue(AdapterErrorPolicy.isClientRejection(typed))
        XCTAssertEqual(AdapterErrorPolicy.failure(error: typed, for: .accepted("pin"), device: device),
                       .failed(device, reason: .pairingRequired, recoverable: true))
    }

    func testClientCertificateRejectionRequiresPinnedPeerAndInitialHandshake() {
        let device = RemoteDevice(id: "tv", name: "Test TV", host: "192.0.2.1", locator: nil)
        let rejection = AndroidTVRemoteControlError.receiveDataError(NWError.tls(errSSLPeerCertUnknown))
        XCTAssertEqual(AdapterErrorPolicy.failure(error: rejection, for: .accepted("pin"), device: device),
                       .failed(device, reason: .pairingRequired, recoverable: true))
        XCTAssertEqual(AdapterErrorPolicy.failure(error: rejection, for: .notEvaluated, device: device),
                       .failed(device, reason: .networkUnreachable, recoverable: true))
        XCTAssertEqual(AdapterErrorPolicy.failure(error: rejection, for: .accepted("pin"), device: device, wasConnected: true),
                       .failed(device, reason: .connectionLost, recoverable: true))
        XCTAssertEqual(AdapterErrorPolicy.failure(error: rejection, for: .changed(expected: "a", actual: "b"), device: device),
                       .failed(device, reason: .trustChanged, recoverable: false))
        let generic = AndroidTVRemoteControlError.receiveDataError(NSError(domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "TLS handshake failed"]))
        XCTAssertEqual(AdapterErrorPolicy.failure(error: generic, for: .accepted("pin"), device: device),
                       .failed(device, reason: .networkUnreachable, recoverable: true))
    }
}
