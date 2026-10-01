package dev.local.androidtvremote

import dev.local.androidtvremote.protocol.ClientIdentityRejectedException
import dev.local.androidtvremote.protocol.remoteHandshakeFailure
import java.io.EOFException
import java.net.SocketException
import java.net.SocketTimeoutException
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLProtocolException
import kotlinx.coroutines.CancellationException
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteHandshakeFailureTests {
    private val pin = "paired-tv-pin"

    @Test
    fun `certificate rejection received after TLS connect enters same-TV pairing`() {
        val error = SSLProtocolException("Read error: OPENSSL_internal:SSLV3_ALERT_CERTIFICATE_UNKNOWN")
        val classified = remoteHandshakeFailure(error, pin, pin)
        assertTrue(classified is ClientIdentityRejectedException)
        assertSame(error, classified.cause)
    }

    @Test
    fun `explicit received client-certificate alerts support Android and JSSE spellings`() {
        for (message in listOf(
            "SSLV3_ALERT_BAD_CERTIFICATE",
            "TLSV1_ALERT_UNKNOWN_CA",
            "tlsv1 alert unknown ca",
            "Received fatal alert: certificate_unknown",
            "Received fatal alert: bad_certificate",
        )) {
            val error = SSLHandshakeException(message)
            val classified = remoteHandshakeFailure(error, pin, pin)
            assertTrue(message, classified is ClientIdentityRejectedException)
            assertSame(error, classified.cause)
        }
    }

    @Test
    fun `unverified or changed TV cannot trigger automatic re-pairing`() {
        val error = SSLProtocolException("SSLV3_ALERT_CERTIFICATE_UNKNOWN")
        assertSame(error, remoteHandshakeFailure(error, null, pin))
        assertSame(error, remoteHandshakeFailure(error, pin, "different-tv-pin"))
    }

    @Test
    fun `other TLS protocol network cancellation and local-validation failures retain their category`() {
        for (error in listOf(
            SSLProtocolException("TLSV1_ALERT_PROTOCOL_VERSION"),
            SSLProtocolException("TLSV1_ALERT_INTERNAL_ERROR"),
            SSLProtocolException("SSLV3_ALERT_BAD_CERTIFICATE_STATUS_RESPONSE"),
            SSLHandshakeException("Local validation failed: certificate_unknown"),
            IllegalStateException("SSLV3_ALERT_CERTIFICATE_UNKNOWN"),
            EOFException(),
            SocketTimeoutException(),
            SocketException(),
            CancellationException(),
        )) {
            assertSame(error, remoteHandshakeFailure(error, pin, pin))
        }
    }
}
