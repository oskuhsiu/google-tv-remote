package dev.local.androidtvremote.protocol

import android.annotation.SuppressLint
import dev.local.androidtvremote.security.IdentityStore
import dev.local.androidtvremote.security.sha256Fingerprint
import java.net.InetSocketAddress
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509KeyManager
import javax.net.ssl.X509TrustManager
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

class TrustChangedException(cause: Throwable? = null) : Exception("TV identity changed", cause)
class ClientIdentityRejectedException(cause: Throwable? = null) : Exception("TV rejected client identity", cause)

data class TlsConnection(
    val socket: SSLSocket,
    val peerCertificate: X509Certificate,
    val peerFingerprint: String,
)

class TlsClient(
    private val identityStore: IdentityStore,
) {
    fun connectPairing(host: String, expectedFingerprint: String? = null): TlsConnection =
        connect(host, PAIRING_PORT, expectedFingerprint)

    suspend fun connectRemote(host: String, expectedFingerprint: String?): TlsConnection =
        withContext(Dispatchers.IO) {
            suspendCancellableCoroutine { continuation ->
                try {
                    val connection = connect(
                        host = host,
                        port = REMOTE_PORT,
                        expectedFingerprint = expectedFingerprint,
                        onSocketCreated = { socket ->
                            continuation.invokeOnCancellation {
                                runCatching { socket.close() }
                            }
                        },
                    )
                    if (continuation.isActive) {
                        continuation.resume(connection)
                    } else {
                        runCatching { connection.socket.close() }
                    }
                } catch (error: Throwable) {
                    if (continuation.isActive) continuation.resumeWithException(error)
                }
            }
        }

    private fun connect(
        host: String,
        port: Int,
        expectedFingerprint: String?,
        onSocketCreated: (SSLSocket) -> Unit = {},
    ): TlsConnection {
        val trustManager = PinningTrustManager(expectedFingerprint)
        val socket = createContext(trustManager).socketFactory.createSocket() as SSLSocket
        onSocketCreated(socket)
        try {
            socket.useClientMode = true
            socket.soTimeout = TRANSPORT_TIMEOUT_MILLIS
            socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MILLIS)
            socket.startHandshake()
            val peer = socket.session.peerCertificates.firstOrNull() as? X509Certificate
                ?: throw SSLHandshakeException("TV did not provide an X.509 certificate")
            return TlsConnection(socket, peer, peer.sha256Fingerprint())
        } catch (error: SSLHandshakeException) {
            runCatching { socket.close() }
            when {
                trustManager.pinMismatch -> throw TrustChangedException(error)
                expectedFingerprint != null && trustManager.pinMatched -> throw ClientIdentityRejectedException(error)
                else -> throw error
            }
        } catch (error: Throwable) {
            runCatching { socket.close() }
            throw error
        }
    }

    private fun createContext(trustManager: X509TrustManager): SSLContext {
        val keyManagerFactory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        keyManagerFactory.init(identityStore.keyStore(), null)
        val hasRsaAlias = keyManagerFactory.keyManagers
            .filterIsInstance<X509KeyManager>()
            .any { manager -> manager.getClientAliases("RSA", null)?.isNotEmpty() == true }
        check(hasRsaAlias) { "AndroidKeyStore identity is unavailable to the TLS key manager" }

        return SSLContext.getInstance("TLS").apply {
            init(keyManagerFactory.keyManagers, arrayOf<TrustManager>(trustManager), null)
        }
    }

    @SuppressLint("CustomX509TrustManager")
    private class PinningTrustManager(
        private val expectedFingerprint: String?,
    ) : X509TrustManager {
        var pinMatched: Boolean = false
            private set
        var pinMismatch: Boolean = false
            private set

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            val certificate = chain?.firstOrNull() ?: throw CertificateException("Empty TV certificate chain")
            if (expectedFingerprint == null) return
            if (certificate.sha256Fingerprint() != expectedFingerprint) {
                pinMismatch = true
                throw CertificateException("TV certificate fingerprint mismatch")
            }
            pinMatched = true
        }

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    companion object {
        const val PAIRING_PORT = 6467
        const val REMOTE_PORT = 6466
        const val CONNECT_TIMEOUT_MILLIS = 8_000
        const val TRANSPORT_TIMEOUT_MILLIS = 8_000
    }
}
