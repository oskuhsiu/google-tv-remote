package dev.local.androidtvremote.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.Date
import javax.security.auth.x500.X500Principal

// Keep certificate material out of accidental toString diagnostics.
class ClientIdentity(
    val privateKey: PrivateKey,
    val certificate: X509Certificate,
    val fingerprint: String,
    val clientName: String? = null,
)

class IdentityStore {
    fun load(): ClientIdentity? {
        val store = keyStore()
        val privateKey = store.getKey(ALIAS, null) as? PrivateKey ?: return null
        val certificate = store.getCertificate(ALIAS) as? X509Certificate ?: return null
        val keyInfo = runCatching {
            KeyFactory.getInstance(privateKey.algorithm, ANDROID_KEY_STORE)
                .getKeySpec(privateKey, KeyInfo::class.java)
        }.getOrNull()
        val requiredPurposes = KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_DECRYPT
        val tlsPolicyMissing = keyInfo != null && (
            KeyProperties.DIGEST_NONE !in keyInfo.digests ||
                keyInfo.purposes and requiredPurposes != requiredPurposes ||
                KeyProperties.ENCRYPTION_PADDING_NONE !in keyInfo.encryptionPaddings ||
                KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1 !in keyInfo.encryptionPaddings
            )
        if (tlsPolicyMissing) {
            store.deleteEntry(ALIAS)
            return null
        }
        return ClientIdentity(privateKey, certificate, certificate.sha256Fingerprint(), CertificateIdentity.uniqueClientName(certificate))
    }

    fun loadOrCreate(): ClientIdentity {
        load()?.let { return it }
        delete()

        val clientName = CertificateIdentity.newClientName()
        val now = System.currentTimeMillis()
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, ANDROID_KEY_STORE)
        generator.initialize(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .setEncryptionPaddings(
                    KeyProperties.ENCRYPTION_PADDING_NONE,
                    KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1,
                )
                .setCertificateSubject(X500Principal("CN=$clientName"))
                .setCertificateSerialNumber(BigInteger.valueOf(now))
                .setCertificateNotBefore(Date(now - ONE_DAY_MILLIS))
                .setCertificateNotAfter(Date(now + TEN_YEARS_MILLIS))
                .setUserAuthenticationRequired(false)
                .build(),
        )
        generator.generateKeyPair()
        return checkNotNull(load()) { "AndroidKeyStore did not retain the generated identity" }
    }

    /** Stage a renamed certificate in memory; leave the hardware key and stored chain untouched. */
    fun prepareUniqueIdentity(existing: ClientIdentity): ClientIdentity {
        if (CertificateIdentity.uniqueClientName(existing.certificate) != null) return existing
        val clientName = CertificateIdentity.newClientName()
        val certificate = CertificateIdentity.selfSigned(existing.privateKey, existing.certificate.publicKey, clientName)
        return ClientIdentity(existing.privateKey, certificate, certificate.sha256Fingerprint(), clientName)
    }

    /** Call only after pairing and the pinned remote handshake; also accepts the old identity for rollback. */
    fun commit(identity: ClientIdentity) {
        val store = keyStore()
        val privateKey = store.getKey(ALIAS, null) as? PrivateKey
            ?: error("Client identity is unavailable")
        val oldChain = store.getCertificateChain(ALIAS)
            ?: error("Client certificate is unavailable")
        check(identity.fingerprint == identity.certificate.sha256Fingerprint()) { "Client certificate fingerprint does not match" }
        identity.certificate.verify(identity.certificate.publicKey)
        identity.certificate.checkValidity()
        // Prove the replacement belongs to the current hardware key, without exporting it.
        val challenge = ByteArray(32).also(java.security.SecureRandom()::nextBytes)
        val signature = java.security.Signature.getInstance("SHA256withRSA").apply {
            initSign(privateKey); update(challenge)
        }.sign()
        check(java.security.Signature.getInstance("SHA256withRSA").apply {
            initVerify(identity.certificate.publicKey); update(challenge)
        }.verify(signature)) { "Client certificate does not match the hardware key" }
        try {
            store.setKeyEntry(ALIAS, privateKey, null, arrayOf(identity.certificate))
        } catch (_: Exception) {
            // Older Keystore implementations update certificate entries in multiple writes.
            runCatching { store.setKeyEntry(ALIAS, privateKey, null, oldChain) }
            throw IllegalStateException("Unable to update the client certificate")
        }
    }

    fun delete() {
        val store = keyStore()
        if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS)
    }

    fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }

    companion object {
        const val ALIAS = "android_tv_remote_client"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val ONE_DAY_MILLIS = 24L * 60 * 60 * 1000
        private const val TEN_YEARS_MILLIS = 10L * 365 * ONE_DAY_MILLIS
    }
}

fun X509Certificate.sha256Fingerprint(): String =
    MessageDigest.getInstance("SHA-256")
        .digest(encoded)
        .joinToString("") { "%02X".format(it) }
