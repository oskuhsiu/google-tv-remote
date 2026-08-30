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

data class ClientIdentity(
    val privateKey: PrivateKey,
    val certificate: X509Certificate,
    val fingerprint: String,
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
        return ClientIdentity(privateKey, certificate, certificate.sha256Fingerprint())
    }

    fun loadOrCreate(): ClientIdentity {
        load()?.let { return it }
        delete()

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
                .setCertificateSubject(X500Principal("CN=TV Remote"))
                .setCertificateSerialNumber(BigInteger.valueOf(now))
                .setCertificateNotBefore(Date(now - ONE_DAY_MILLIS))
                .setCertificateNotAfter(Date(now + TEN_YEARS_MILLIS))
                .setUserAuthenticationRequired(false)
                .build(),
        )
        generator.generateKeyPair()
        return checkNotNull(load()) { "AndroidKeyStore did not retain the generated identity" }
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
