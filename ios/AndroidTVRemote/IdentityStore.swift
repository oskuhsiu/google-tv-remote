import CryptoKit
import Foundation
import Security
import X509

struct ClientIdentity {
    let identity: SecIdentity
    let certificate: SecCertificate
    let publicKey: SecKey
    let fingerprint: String

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

final class IdentityStore {
    private let keyTag: Data
    private let certificateLabel: String

    init(namespace: String = "production") {
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
                fingerprint: CertificateFingerprint.sha256(certificate)
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
            fingerprint: CertificateFingerprint.sha256(certificate)
        )
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

    private func createIdentity() throws -> ClientIdentity {
        let privateKey = try createPrivateKey()
        do {
            let certificate = try createCertificate(privateKey: privateKey)
            try saveCertificate(certificate)
            guard let identity = makeIdentity(certificate: certificate, privateKey: privateKey) else {
                throw IdentityStoreError.identityCreation
            }
            return ClientIdentity(
                identity: identity,
                certificate: certificate,
                publicKey: SecKeyCopyPublicKey(privateKey)!,
                fingerprint: CertificateFingerprint.sha256(certificate)
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

    private func createCertificate(privateKey: SecKey) throws -> SecCertificate {
        let signingKey = try Certificate.PrivateKey(privateKey)
        let name = try DistinguishedName {
            CommonName("Android TV Remote")
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
