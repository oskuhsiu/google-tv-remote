package dev.local.androidtvremote.security

import java.io.ByteArrayInputStream
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPrivateKey
import java.security.interfaces.RSAPublicKey
import org.junit.Assert.*
import org.junit.Test

class CertificateIdentityTests {
    @Test fun uniqueNamesContainRandom128BitSuffix() {
        val first = CertificateIdentity.newClientName()
        val second = CertificateIdentity.newClientName()
        assertTrue(Regex("TV Remote-[0-9a-f]{32}").matches(first))
        assertTrue(Regex("TV Remote-[0-9a-f]{32}").matches(second))
        assertNotEquals(first, second)
    }

    @Test fun replacementCertificateUsesTheSameKeyAndIsIndependentlyVerifiable() {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val name = CertificateIdentity.newClientName()
        val certificate = CertificateIdentity.selfSigned(pair.private, pair.public, name)
        val parsed = CertificateFactory.getInstance("X.509").generateCertificate(
            ByteArrayInputStream(certificate.encoded)) as X509Certificate
        parsed.verify(pair.public)
        parsed.checkValidity()
        assertEquals(2048, (parsed.publicKey as RSAPublicKey).modulus.bitLength())
        assertEquals("SHA256withRSA", parsed.sigAlgName)
        assertEquals(parsed.subjectX500Principal, parsed.issuerX500Principal)
        assertEquals("CN=$name", parsed.subjectX500Principal.name)
        assertEquals(name, CertificateIdentity.uniqueClientName(parsed))
        assertArrayEquals(pair.public.encoded, parsed.publicKey.encoded)
        val challenge = "Independent certificate key matching challenge".toByteArray()
        val signature = Signature.getInstance("SHA256withRSA").apply { initSign(pair.private); update(challenge) }.sign()
        assertTrue(Signature.getInstance("SHA256withRSA").apply { initVerify(parsed.publicKey); update(challenge) }.verify(signature))
    }

    @Test fun stagedReplacementDoesNotExportPrivateKey() {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val key = pair.private as RSAPrivateKey
        val nonExportable = object : RSAPrivateKey {
            override fun getAlgorithm() = "RSA"
            override fun getFormat(): String? = null
            override fun getEncoded(): ByteArray = error("Private key export is forbidden")
            override fun getModulus() = key.modulus
            override fun getPrivateExponent() = key.privateExponent
        }
        val certificate = CertificateIdentity.selfSigned(nonExportable, pair.public, CertificateIdentity.newClientName())
        certificate.verify(pair.public)
        assertArrayEquals(pair.public.encoded, certificate.publicKey.encoded)
    }

    @Test fun alreadyUniqueIdentityIsNotRotatedByRepairPreparation() {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val name = CertificateIdentity.newClientName()
        val certificate = CertificateIdentity.selfSigned(pair.private, pair.public, name)
        val existing = ClientIdentity(pair.private, certificate, certificate.sha256Fingerprint(), name)
        val prepared = IdentityStore().prepareUniqueIdentity(existing)
        assertSame(existing, prepared)
        assertSame(existing.privateKey, prepared.privateKey)
        assertArrayEquals(existing.certificate.encoded, prepared.certificate.encoded)
    }

    @Test fun legacyRepairStagesOnlyANewCertificateAndLeavesExistingIdentityUntouched() {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val original = CertificateIdentity.selfSigned(pair.private, pair.public, CertificateIdentity.newClientName())
        // Make a valid non-unique-name fixture by changing its same-length CN prefix and re-signing.
        val encoded = original.encoded.copyOf()
        val before = "TV Remote-".toByteArray()
        val after = "OldRemote-".toByteArray()
        for (offset in 0..encoded.size - before.size) {
            if (before.indices.all { encoded[offset + it] == before[it] }) after.copyInto(encoded, offset)
        }
        fun parse(bytes: ByteArray) = CertificateFactory.getInstance("X.509").generateCertificate(
            ByteArrayInputStream(bytes)) as X509Certificate
        val tbs = parse(encoded).tbsCertificate
        val signature = Signature.getInstance("SHA256withRSA").apply { initSign(pair.private); update(tbs) }.sign()
        signature.copyInto(encoded, encoded.size - signature.size)
        val oldCertificate = parse(encoded)
        oldCertificate.verify(pair.public)
        assertNull(CertificateIdentity.uniqueClientName(oldCertificate))
        val existing = ClientIdentity(pair.private, oldCertificate, oldCertificate.sha256Fingerprint())
        val prepared = IdentityStore().prepareUniqueIdentity(existing)
        assertSame(existing.privateKey, prepared.privateKey)
        assertArrayEquals(existing.certificate.publicKey.encoded, prepared.certificate.publicKey.encoded)
        assertArrayEquals(encoded, existing.certificate.encoded)
        assertNotEquals(existing.fingerprint, prepared.fingerprint)
        assertEquals(prepared.clientName, CertificateIdentity.uniqueClientName(prepared.certificate))
        prepared.certificate.verify(pair.public)
    }

    @Test fun uniqueNameRecognitionDoesNotAcceptLegacyOrMalformedCommonNames() {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val certificate = CertificateIdentity.selfSigned(pair.private, pair.public, CertificateIdentity.newClientName())
        assertNotNull(CertificateIdentity.uniqueClientName(certificate))
        try {
            CertificateIdentity.selfSigned(pair.private, pair.public, "TV Remote")
            fail("Legacy name must not be used for a replacement certificate")
        } catch (_: IllegalArgumentException) { }
    }
}
