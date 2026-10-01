package dev.local.androidtvremote.security

import java.io.ByteArrayInputStream
import java.math.BigInteger
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.security.auth.x500.X500Principal

/** Limited DER encoder for a client certificate signed with its existing RSA key. */
object CertificateIdentity {
    fun newClientName(): String = "TV Remote-" + ByteArray(16).also(SecureRandom()::nextBytes)
        .joinToString("") { "%02x".format(it) }

    fun uniqueClientName(certificate: X509Certificate): String? =
        Regex("CN=(TV Remote-[0-9a-f]{32})").matchEntire(certificate.subjectX500Principal.name)?.groupValues?.get(1)

    fun selfSigned(privateKey: PrivateKey, publicKey: PublicKey, clientName: String): X509Certificate {
        require(Regex("TV Remote-[0-9a-f]{32}").matches(clientName)) { "Invalid client identity name" }
        require(privateKey.algorithm == "RSA" && publicKey.algorithm == "RSA") { "RSA identity required" }
        val random = SecureRandom()
        val name = X500Principal("CN=$clientName").encoded
        // sha256WithRSAEncryption, including its NULL parameters.
        val algorithm = byteArrayOf(0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86.toByte(), 0x48, 0x86.toByte(),
            0xf7.toByte(), 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00)
        val now = System.currentTimeMillis()
        val serial = BigInteger(1, ByteArray(16).also(random::nextBytes)).add(BigInteger.ONE)
        val validity = sequence(time(Date(now - DAY)), time(Date(now + 10L * 365 * DAY)))
        val tbs = sequence(der(0xa0, der(0x02, byteArrayOf(2))), der(0x02, serial.toByteArray()),
            algorithm, name, validity, name, publicKey.encoded)
        val signature = Signature.getInstance("SHA256withRSA").apply { initSign(privateKey); update(tbs) }.sign()
        val encoded = sequence(tbs, algorithm, der(0x03, byteArrayOf(0) + signature))
        val certificate = CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(encoded)) as X509Certificate
        certificate.verify(publicKey)
        certificate.checkValidity()
        return certificate
    }

    private fun time(date: Date): ByteArray {
        val utc = TimeZone.getTimeZone("UTC")
        val year = SimpleDateFormat("yyyy", Locale.US).apply { timeZone = utc }.format(date).toInt()
        val isUtcTime = year in 1950..2049
        val pattern = if (isUtcTime) "yyMMddHHmmss'Z'" else "yyyyMMddHHmmss'Z'"
        val text = SimpleDateFormat(pattern, Locale.US).apply { timeZone = utc }.format(date)
        return der(if (isUtcTime) 0x17 else 0x18, text.toByteArray(Charsets.US_ASCII))
    }
    private fun sequence(vararg items: ByteArray) = der(0x30, items.fold(ByteArray(0)) { result, item -> result + item })
    private fun der(tag: Int, bytes: ByteArray): ByteArray {
        val length = if (bytes.size < 128) byteArrayOf(bytes.size.toByte()) else {
            val encoded = BigInteger.valueOf(bytes.size.toLong()).toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
            byteArrayOf((0x80 or encoded.size).toByte()) + encoded
        }
        return byteArrayOf(tag.toByte()) + length + bytes
    }
    private const val DAY = 86_400_000L
}
