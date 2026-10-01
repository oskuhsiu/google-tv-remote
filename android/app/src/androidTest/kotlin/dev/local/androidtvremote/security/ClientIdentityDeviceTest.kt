package dev.local.androidtvremote.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.local.androidtvremote.protocol.IdentityKeyManager
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.X509Certificate
import java.util.Date
import java.util.UUID
import javax.net.ssl.SSLContext
import javax.security.auth.x500.X500Principal
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the device's Keystore provider using a disposable alias and no TV connection. */
@RunWith(AndroidJUnit4::class)
class ClientIdentityDeviceTest {
    @Test
    fun stagesAndCommitsUniqueCertificateWithoutReplacingHardwareKeyOrProductionIdentity() {
        val productionBefore = IdentityStore().load()?.fingerprint
        val alias = "android_tv_remote_disposable_test_${UUID.randomUUID()}"
        val store = openStore()
        assertTrue("Test alias must be isolated", alias != IdentityStore.ALIAS && !store.containsAlias(alias))
        try {
            val now = System.currentTimeMillis()
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
            generator.initialize(
                KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(2048)
                    .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256)
                    .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE, KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
                    .setCertificateSubject(X500Principal("CN=TV Remote"))
                    .setCertificateSerialNumber(BigInteger(128, SecureRandom()).add(BigInteger.ONE))
                    .setCertificateNotBefore(Date(now - DAY))
                    .setCertificateNotAfter(Date(now + 10L * 365 * DAY))
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
            generator.generateKeyPair()
            val privateKey = store.getKey(alias, null) as PrivateKey
            val original = store.getCertificate(alias) as X509Certificate
            val originalBytes = original.encoded
            assertTrue("Device key must not export private material", privateKey.encoded == null)
            assertTrue("Fixture must have the legacy CN", original.subjectX500Principal.name == "CN=TV Remote")
            verifyKey(privateKey, original)

            val name = CertificateIdentity.newClientName()
            val stagedCertificate = CertificateIdentity.selfSigned(privateKey, original.publicKey, name)
            stagedCertificate.verify(original.publicKey)
            stagedCertificate.checkValidity()
            val staged = ClientIdentity(privateKey, stagedCertificate, stagedCertificate.sha256Fingerprint(), name)
            assertTrue("Staged certificate must have a unique CN", CertificateIdentity.uniqueClientName(stagedCertificate) == name)
            assertTrue("New identities need distinct names", name != CertificateIdentity.newClientName())
            assertTrue("Staging must retain the original public key", stagedCertificate.publicKey.encoded.contentEquals(original.publicKey.encoded))
            assertTrue("Staging must leave the persisted certificate unchanged",
                openStore().getCertificate(alias).encoded.contentEquals(originalBytes))

            val manager = IdentityKeyManager(staged)
            val tlsAlias = manager.chooseClientAlias(arrayOf("RSA"), null, null)
            assertTrue("TLS must select the staged RSA identity", tlsAlias != null)
            assertTrue("TLS must present the staged certificate", manager.getCertificateChain(tlsAlias)?.firstOrNull() === stagedCertificate)
            assertTrue("TLS must use the existing hardware key", manager.getPrivateKey(tlsAlias) === privateKey)
            assertTrue("TLS must not offer an EC identity", manager.chooseClientAlias(arrayOf("EC"), null, null) == null)
            SSLContext.getInstance("TLS").init(arrayOf(manager), null, null)
            verifyKey(manager.getPrivateKey(tlsAlias)!!, original)
            assertTrue("Preparing TLS must not commit the staged certificate",
                openStore().getCertificate(alias).encoded.contentEquals(originalBytes))

            // Exercise the same native certificate-chain operation used by IdentityStore.commit.
            store.setKeyEntry(alias, privateKey, null, arrayOf(stagedCertificate))
            val reopened = openStore()
            val committed = reopened.getCertificate(alias) as X509Certificate
            val retainedKey = reopened.getKey(alias, null) as PrivateKey
            assertTrue("Committed CN must survive a fresh store load", CertificateIdentity.uniqueClientName(committed) == name)
            assertTrue("Committed fingerprint must survive a fresh store load", committed.sha256Fingerprint() == staged.fingerprint)
            assertTrue("Committed certificate must retain exact DER", committed.encoded.contentEquals(stagedCertificate.encoded))
            assertTrue("Certificate update must not replace the public key", committed.publicKey.encoded.contentEquals(original.publicKey.encoded))
            assertTrue("Committed hardware key must remain non-exportable", retainedKey.encoded == null)
            verifyKey(retainedKey, original)
            assertTrue("Another store load must retain the committed certificate",
                openStore().getCertificate(alias).encoded.contentEquals(stagedCertificate.encoded))

            // Prove the same operation can restore the original certificate for coordinator rollback.
            reopened.setKeyEntry(alias, retainedKey, null, arrayOf(original))
            assertTrue("Rollback must restore the original certificate",
                openStore().getCertificate(alias).encoded.contentEquals(originalBytes))
            verifyKey(openStore().getKey(alias, null) as PrivateKey, original)
        } finally {
            if (store.containsAlias(alias)) store.deleteEntry(alias)
            assertTrue("Production identity must remain unchanged", productionBefore == IdentityStore().load()?.fingerprint)
        }
    }

    private fun verifyKey(privateKey: PrivateKey, certificate: X509Certificate) {
        val challenge = "Disposable Keystore identity verification".toByteArray(Charsets.UTF_8)
        val signature = Signature.getInstance("SHA256withRSA").apply { initSign(privateKey); update(challenge) }.sign()
        assertTrue("Hardware key must match the original public key", Signature.getInstance("SHA256withRSA").apply {
            initVerify(certificate.publicKey); update(challenge)
        }.verify(signature))
    }

    private fun openStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private companion object { const val DAY = 86_400_000L }
}
