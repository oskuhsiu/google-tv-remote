package dev.local.androidtvremote

import dev.local.androidtvremote.protocol.ClientIdentityRejectedException
import dev.local.androidtvremote.protocol.TcpConnectException
import dev.local.androidtvremote.protocol.TrustChangedException
import java.net.SocketTimeoutException
import javax.net.ssl.SSLHandshakeException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class RememberedTvConnectionTests {
    private val oldAddress = TvCandidate("local.|_androidtvremote2._tcp|Living Room", "Living Room", "192.168.31.38", TvSource.DISCOVERY)
    private val currentAddress = oldAddress.copy(host = "192.168.31.40")
    private val pin = "original-paired-tv-pin"

    @Test
    fun `working remembered address connects directly without resolution`() = runTest {
        val result = openRememberedTvSession(oldAddress, pin, oldAddress.locatorKey,
            resolve = { error("A reachable TV must not be resolved") },
            open = { candidate, expectedPin ->
                assertEquals(oldAddress, candidate)
                assertEquals(pin, expectedPin)
                "authenticated-session"
            },
        )
        assertEquals(oldAddress, result.candidate)
        assertEquals("authenticated-session", result.session)
    }

    @Test
    fun `stale address resolves remembered service once and connects with original pin`() = runTest {
        val attempts = mutableListOf<Pair<TvCandidate, String>>()
        var resolutions = 0
        var notifiedAddress: TvCandidate? = null
        val result = openRememberedTvSession(oldAddress, pin, oldAddress.locatorKey,
            resolve = { locator ->
                assertEquals(oldAddress.locatorKey, locator)
                resolutions++
                currentAddress
            },
            open = { candidate, expectedPin ->
                attempts += candidate to expectedPin
                if (candidate.host == oldAddress.host) throw TcpConnectException(SocketTimeoutException())
                "authenticated-session"
            },
            onAddressResolved = { notifiedAddress = it },
        )
        assertEquals(listOf(oldAddress to pin, currentAddress to pin), attempts)
        assertEquals(1, resolutions)
        assertEquals(currentAddress, notifiedAddress)
        assertEquals(currentAddress, result.candidate)
        assertEquals("authenticated-session", result.session)
    }

    @Test
    fun `manual or legacy record without locator retains original failure`() = runTest {
        val failure = TcpConnectException(SocketTimeoutException())
        for (locator in listOf(null, "", "manual:192.168.31.38", "local.|_other._tcp|Living Room")) {
            val observed = failureOf {
                openRememberedTvSession(oldAddress, pin, locator,
                    resolve = { error("No valid TV service locator to resolve") },
                    open = { _, _ -> throw failure },
                )
            }
            assertSame(failure, observed)
        }
    }

    @Test
    fun `missing service or unchanged address does not retry stale endpoint`() = runTest {
        for (resolved in listOf(null, oldAddress, currentAddress.copy(locatorKey = "other-service"), currentAddress.copy(host = ""))) {
            var attempts = 0
            val failure = TcpConnectException(SocketTimeoutException())
            val observed = failureOf {
                openRememberedTvSession(oldAddress, pin, oldAddress.locatorKey,
                    resolve = { resolved },
                    open = { _, _ -> attempts++; throw failure },
                )
            }
            assertSame(failure, observed)
            assertEquals(1, attempts)
        }
    }

    @Test
    fun `TLS trust auth and protocol timeouts do not trigger address recovery`() = runTest {
        for (failure in listOf(TrustChangedException(), ClientIdentityRejectedException(), SSLHandshakeException("handshake failed"), SocketTimeoutException("protocol timeout"))) {
            val observed = failureOf {
                openRememberedTvSession(oldAddress, pin, oldAddress.locatorKey,
                    resolve = { error("Only TCP establishment failure permits resolution") },
                    open = { _, _ -> throw failure },
                )
            }
            assertSame(failure, observed)
        }
    }

    @Test
    fun `changed peer at recovered address cannot yield a session`() = runTest {
        val rejected = TrustChangedException()
        val observed = failureOf {
            openRememberedTvSession(oldAddress, pin, oldAddress.locatorKey,
                resolve = { currentAddress },
                open = { candidate, expectedPin ->
                    assertEquals(pin, expectedPin)
                    if (candidate.host == oldAddress.host) throw TcpConnectException(SocketTimeoutException())
                    throw rejected
                },
            )
        }
        assertSame(rejected, observed)
    }

    @Test
    fun `cancellation while resolving cannot connect or publish a late address`() = runTest {
        val resolved = CompletableDeferred<TvCandidate?>()
        var attempts = 0
        var addressPublished = false
        val job = async {
            openRememberedTvSession(oldAddress, pin, oldAddress.locatorKey,
                resolve = { resolved.await() },
                open = { _, _ -> attempts++; throw TcpConnectException(SocketTimeoutException()) },
                onAddressResolved = { addressPublished = true },
            )
        }
        runCurrent()
        job.cancel()
        resolved.complete(currentAddress)
        runCurrent()
        assertTrue(job.isCancelled)
        assertEquals(1, attempts)
        assertTrue(!addressPublished)
    }

    private suspend fun failureOf(block: suspend () -> Unit): Throwable = try {
        block()
        error("Expected connection failure")
    } catch (failure: Throwable) {
        failure
    }
}
