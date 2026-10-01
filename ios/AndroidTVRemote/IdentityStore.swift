import CryptoKit
import Foundation
import Security
import UIKit
import X509

struct ClientIdentity {
    let identity: SecIdentity
    let certificate: SecCertificate
    let publicKey: SecKey
    let fingerprint: String
    let privateKey: SecKey
    let clientName: String

    var tlsImportItems: CFArray {
        [[kSecImportItemIdentity as String: identity]] as CFArray
    }
}

enum IdentityStoreError: Error, Equatable {
    case keychain(operation: String, status: OSStatus)
    case randomGeneration(status: OSStatus)
    case certificateCreation
    case identityCreation
}

final class ClientNameStore {
    private let service: String
    private let account = "device-suffix"

    init(namespace: String = "production") {
        service = "dev.local.AndroidTVRemote.client-name.\(namespace)"
    }

    func loadOrCreate() -> String {
        do {
            if let suffix = try loadSuffix() {
                return "TV Remote-\(suffix)"
            }
        } catch {
            return "TV Remote-\(generatedSuffix())"
        }

        let suffix = generatedSuffix()
        try? saveSuffix(suffix)
        return "TV Remote-\(suffix)"
    }

    static func generateUniqueName() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw IdentityStoreError.randomGeneration(status: status) }
        return "TV Remote-" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func generatedSuffix() -> String {
        let source = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        return SHA256.hash(data: Data(source.utf8))
            .prefix(3)
            .map { String(format: "%02X", $0) }
            .joined()
    }

    private func loadSuffix() throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary,
            &result
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let suffix = String(data: data, encoding: .utf8),
              suffix.count == 6 else {
            throw IdentityStoreError.keychain(operation: "load client name", status: status)
        }
        return suffix
    }

    private func saveSuffix(_ suffix: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(suffix.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw IdentityStoreError.keychain(operation: "update client name", status: updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw IdentityStoreError.keychain(operation: "save client name", status: status)
        }
    }
}

final class IdentityStore {
    private let keyTag: Data
    private let certificateLabel: String
    private let clientNameStore: ClientNameStore

    init(namespace: String = "production") {
        clientNameStore = ClientNameStore(namespace: namespace)
        let prefix = "dev.local.AndroidTVRemote.identity.\(namespace)"
        keyTag = Data("\(prefix).key".utf8)
        certificateLabel = "\(prefix).certificate"
    }

    func loadOrCreate() throws -> ClientIdentity {
        let key = try loadPrivateKey()
        let certificate = try loadCertificate()

        if let key, let certificate, let identity = makeIdentity(certificate: certificate, privateKey: key) {
            return ClientIdentity(
                identity: identity,
                certificate: certificate,
                publicKey: SecKeyCopyPublicKey(key)!,
                fingerprint: CertificateFingerprint.sha256(certificate),
                privateKey: key, clientName: clientName(for: certificate)
            )
        }

        if key != nil || certificate != nil {
            try deleteAll()
        }
        return try createIdentity()
    }

    func load() throws -> ClientIdentity? {
        guard let key = try loadPrivateKey(), let certificate = try loadCertificate() else {
            return nil
        }
        guard let identity = makeIdentity(certificate: certificate, privateKey: key) else {
            return nil
        }
        return ClientIdentity(
            identity: identity,
            certificate: certificate,
            publicKey: SecKeyCopyPublicKey(key)!,
            fingerprint: CertificateFingerprint.sha256(certificate),
            privateKey: key, clientName: clientName(for: certificate)
        )
    }

    private func clientName(for certificate: SecCertificate) -> String {
        if let name = SecCertificateCopySubjectSummary(certificate) as String?, Self.isUniqueName(name) { return name }
        return clientNameStore.loadOrCreate()
    }

    static func isUniqueName(_ name: String) -> Bool {
        let prefix = "TV Remote-"
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.count)
        return suffix.utf8.count == 32 && suffix.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Repair only the client certificate; the existing Keychain private key is unchanged.
    func identityForRepair() throws -> ClientIdentity {
        guard let existing = try load() else { throw IdentityStoreError.identityCreation }
        let commonName = SecCertificateCopySubjectSummary(existing.certificate) as String? ?? ""
        if Self.isUniqueName(commonName) { return existing }
        let certificate = try createCertificate(privateKey: existing.privateKey, commonName: ClientNameStore.generateUniqueName())
        guard let identity = makeIdentity(certificate: certificate, privateKey: existing.privateKey) else {
            throw IdentityStoreError.identityCreation
        }
        return ClientIdentity(identity: identity, certificate: certificate, publicKey: existing.publicKey,
            fingerprint: CertificateFingerprint.sha256(certificate), privateKey: existing.privateKey,
            clientName: clientName(for: certificate))
    }

    /// Called only after pinned pairing and authenticated remote handshake, with rollback on metadata failure.
    func commitCertificate(_ identity: ClientIdentity, persistMetadata: () throws -> Void) throws {
        guard let original = try loadCertificate() else { throw IdentityStoreError.identityCreation }
        if CertificateFingerprint.sha256(original) == identity.fingerprint {
            try persistMetadata()
            return
        }
        try replaceCertificate(identity.certificate)
        do { try persistMetadata() }
        catch {
            try replaceCertificate(original)
            throw error
        }
    }

    private func replaceCertificate(_ certificate: SecCertificate) throws {
        let original = try loadCertificate()
        try deleteItem(query: [kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: certificateLabel], operation: "replace certificate")
        do { try saveCertificate(certificate) }
        catch {
            if let original { try saveCertificate(original) }
            throw error
        }
    }

    func status(matching fingerprint: String) throws -> ClientIdentityStatus {
        guard let identity = try load() else { return .missing }
        return identity.fingerprint == fingerprint ? .matches : .mismatch
    }

    func deleteIdentity() throws {
        try deleteAll()
    }

    func deleteAll() throws {
        var firstError: Error?
        do {
            try deleteItem(
                query: [
                    kSecClass as String: kSecClassKey,
                    kSecAttrApplicationTag as String: keyTag,
                    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                ],
                operation: "delete private key"
            )
        } catch {
            firstError = error
        }
        do {
            try deleteItem(
                query: [
                    kSecClass as String: kSecClassCertificate,
                    kSecAttrLabel as String: certificateLabel,
                ],
                operation: "delete certificate"
            )
        } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError { throw firstError }
    }

#if DEBUG
    func createLegacyIdentityForTesting() throws -> ClientIdentity {
        let privateKey = try createPrivateKey()
        let certificate = try createCertificate(privateKey: privateKey, commonName: "Android TV Remote")
        try saveCertificate(certificate)
        guard let identity = makeIdentity(certificate: certificate, privateKey: privateKey) else { throw IdentityStoreError.identityCreation }
        return ClientIdentity(identity: identity, certificate: certificate, publicKey: SecKeyCopyPublicKey(privateKey)!,
            fingerprint: CertificateFingerprint.sha256(certificate), privateKey: privateKey, clientName: clientName(for: certificate))
    }
#endif

    private func createIdentity() throws -> ClientIdentity {
        let privateKey = try createPrivateKey()
        do {
            let certificate = try createCertificate(privateKey: privateKey, commonName: ClientNameStore.generateUniqueName())
            try saveCertificate(certificate)
            guard let identity = makeIdentity(certificate: certificate, privateKey: privateKey) else {
                throw IdentityStoreError.identityCreation
            }
            return ClientIdentity(
                identity: identity,
                certificate: certificate,
                publicKey: SecKeyCopyPublicKey(privateKey)!,
                fingerprint: CertificateFingerprint.sha256(certificate),
                privateKey: privateKey, clientName: clientName(for: certificate)
            )
        } catch {
            try? deleteAll()
            throw error
        }
    }

    private func createPrivateKey() throws -> SecKey {
        let privateAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrIsExtractable as String: false,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2_048,
            kSecPrivateKeyAttrs as String: privateAttributes,
        ]

        var unmanagedError: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &unmanagedError) else {
            if let error = unmanagedError?.takeRetainedValue() {
                throw error
            }
            throw IdentityStoreError.certificateCreation
        }
        return key
    }

    private func createCertificate(privateKey: SecKey, commonName: String) throws -> SecCertificate {
        let signingKey = try Certificate.PrivateKey(privateKey)
        let name = try DistinguishedName {
            CommonName(commonName)
        }

        var serial = [UInt8](repeating: 0, count: 16)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        guard randomStatus == errSecSuccess else {
            throw IdentityStoreError.randomGeneration(status: randomStatus)
        }
        serial[0] &= 0x7f
        if serial.allSatisfy({ $0 == 0 }) {
            serial[serial.count - 1] = 1
        }

        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(bytes: serial),
            publicKey: signingKey.publicKey,
            notValidBefore: now.addingTimeInterval(-300),
            notValidAfter: now.addingTimeInterval(10 * 365 * 24 * 60 * 60),
            issuer: name,
            subject: name,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: Certificate.Extensions {},
            issuerPrivateKey: signingKey
        )
        return try SecCertificate.makeWithCertificate(certificate)
    }

    private func saveCertificate(_ certificate: SecCertificate) throws {
        let status = SecItemAdd(
            [
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: certificateLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueRef as String: certificate,
            ] as CFDictionary,
            nil
        )
        guard status == errSecSuccess else {
            throw IdentityStoreError.keychain(operation: "save certificate", status: status)
        }
    }

    private func loadPrivateKey() throws -> SecKey? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecReturnRef as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary,
            &result
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let key = result as! SecKey? else {
            throw IdentityStoreError.keychain(operation: "load private key", status: status)
        }
        return key
    }

    private func loadCertificate() throws -> SecCertificate? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: certificateLabel,
                kSecReturnRef as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary,
            &result
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let certificate = result as! SecCertificate? else {
            throw IdentityStoreError.keychain(operation: "load certificate", status: status)
        }
        return certificate
    }

    private func makeIdentity(certificate: SecCertificate, privateKey: SecKey) -> SecIdentity? {
        SecIdentityCreate(nil, certificate, privateKey)
    }

    private func deleteItem(query: [String: Any], operation: String) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw IdentityStoreError.keychain(operation: operation, status: status)
        }
    }
}

enum CertificateFingerprint {
    static func sha256(_ certificate: SecCertificate) -> String {
        let bytes = Data(SecCertificateCopyData(certificate) as Data)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func leafCertificate(from trust: SecTrust) -> SecCertificate? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return nil
        }
        return chain.first
    }
}
