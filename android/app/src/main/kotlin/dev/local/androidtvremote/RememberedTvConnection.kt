package dev.local.androidtvremote

import dev.local.androidtvremote.discovery.RememberedTvService
import dev.local.androidtvremote.protocol.TcpConnectException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal data class OpenedTvSession<T>(val candidate: TvCandidate, val session: T)

internal suspend fun <T> openRememberedTvSession(
    candidate: TvCandidate,
    expectedFingerprint: String,
    locatorKey: String?,
    resolve: suspend (String) -> TvCandidate?,
    open: suspend (TvCandidate, String) -> T,
    onAddressResolved: (TvCandidate) -> Unit = {},
): OpenedTvSession<T> {
    val failure = try {
        return OpenedTvSession(candidate, open(candidate, expectedFingerprint))
    } catch (error: TcpConnectException) {
        error
    }
    val service = RememberedTvService.parse(locatorKey) ?: throw failure
    val resolved = resolve(service.locatorKey) ?: throw failure
    currentCoroutineContext().ensureActive()
    if (resolved.host.isBlank() || resolved.host == candidate.host || resolved.locatorKey != service.locatorKey) {
        throw failure
    }
    onAddressResolved(resolved)
    return OpenedTvSession(resolved, open(resolved, expectedFingerprint))
}
