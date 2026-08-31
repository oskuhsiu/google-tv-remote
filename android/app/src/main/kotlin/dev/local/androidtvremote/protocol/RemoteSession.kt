package dev.local.androidtvremote.protocol

import dev.local.androidtvremote.RemoteCommand
import dev.local.androidtvremote.RemoteKeyAction
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.async
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import remote.Remotemessage.RemoteConfigure
import remote.Remotemessage.RemoteDeviceInfo
import remote.Remotemessage.RemoteMessage
import remote.Remotemessage.RemoteSetActive

class RemoteSession private constructor(
    private val connection: TlsConnection,
    private val scope: CoroutineScope,
    private val onLost: (Throwable?) -> Unit,
    private val frameReader: DelimitedFrameReader,
) {
    private val input: InputStream = connection.socket.inputStream
    private val writer = SerializedWriter(connection.socket.outputStream)
    private val closed = AtomicBoolean(false)
    private var readerJob: Job? = null
    private var activeFeatures = CLIENT_FEATURES
    private val voiceMutex = Mutex()
    private var pendingVoiceBegin: CompletableDeferred<Int>? = null
    private val voiceGate = VoiceSessionGate()

    val peerFingerprint: String
        get() = connection.peerFingerprint

    val supportsVoice: Boolean
        get() = activeFeatures and FEATURE_VOICE != 0

    suspend fun send(command: RemoteCommand, action: RemoteKeyAction = RemoteKeyAction.SHORT) {
        check(!closed.get()) { "Remote session is closed" }
        sendWithTimeout(
            message = RemoteMessageFactory.key(command, action),
            timeoutMillis = KEY_SEND_TIMEOUT_MILLIS,
            timeoutMessage = "Remote key write timed out",
        )
    }

    private suspend fun sendWithTimeout(
        message: RemoteMessage,
        timeoutMillis: Long,
        timeoutMessage: String,
    ) {
        withContext(NonCancellable) {
            supervisorScope {
                val sendJob = async(start = CoroutineStart.UNDISPATCHED) {
                    runCatching { writer.send(message) }
                }
                val outcome = withTimeoutOrNull(timeoutMillis) {
                    sendJob.await()
                }
                if (outcome == null) {
                    runCatching { connection.socket.close() }
                    sendJob.cancelAndJoin()
                    throw SocketTimeoutException(timeoutMessage)
                }
                outcome.getOrThrow()
            }
        }
    }

    suspend fun beginVoice(): Int {
        check(!closed.get()) { "Remote session is closed" }
        check(supportsVoice) { "TV did not negotiate voice support" }
        val waiter = CompletableDeferred<Int>()
        voiceMutex.withLock {
            voiceGate.startWaiting()
            pendingVoiceBegin = waiter
        }
        try {
            sendWithTimeout(
                RemoteMessageFactory.search(),
                VOICE_SEND_TIMEOUT_MILLIS,
                "Voice search write timed out",
            )
            val sessionId = withTimeoutOrNull(VOICE_BEGIN_TIMEOUT_MILLIS) { waiter.await() }
                ?: throw SocketTimeoutException("TV did not begin a voice session")
            voiceMutex.withLock { pendingVoiceBegin = null }
            try {
                sendWithTimeout(
                    RemoteMessageFactory.voiceBegin(sessionId),
                    VOICE_SEND_TIMEOUT_MILLIS,
                    "Voice begin write timed out",
                )
            } catch (error: Throwable) {
                withContext(NonCancellable) {
                    val shouldEnd = voiceMutex.withLock {
                        voiceGate.takeEnd(sessionId)
                    }
                    if (shouldEnd) runCatching { sendVoiceEndMessage(sessionId) }
                }
                throw error
            }
            return sessionId
        } finally {
            withContext(NonCancellable) {
                val orphanedSessionId = voiceMutex.withLock {
                    if (pendingVoiceBegin === waiter) {
                        pendingVoiceBegin = null
                        voiceGate.cancelAndTakeActive()
                    } else {
                        null
                    }
                }
                orphanedSessionId?.let { sessionId ->
                    runCatching {
                        sendWithTimeout(
                            RemoteMessageFactory.voiceBegin(sessionId),
                            VOICE_SEND_TIMEOUT_MILLIS,
                            "Voice begin write timed out",
                        )
                    }
                    runCatching { sendVoiceEndMessage(sessionId) }
                }
            }
        }
    }

    suspend fun sendVoicePayload(sessionId: Int, samples: ByteArray) {
        val isActive = voiceMutex.withLock { voiceGate.isActive(sessionId) }
        if (!isActive) return
        sendWithTimeout(
            RemoteMessageFactory.voicePayload(sessionId, samples),
            VOICE_SEND_TIMEOUT_MILLIS,
            "Voice payload write timed out",
        )
    }

    suspend fun endVoice(sessionId: Int) {
        val shouldSend = voiceMutex.withLock { voiceGate.takeEnd(sessionId) }
        if (shouldSend) sendVoiceEndMessage(sessionId)
    }

    private suspend fun sendVoiceEndMessage(sessionId: Int) {
        if (closed.get()) return
        sendWithTimeout(
            RemoteMessageFactory.voiceEnd(sessionId),
            VOICE_SEND_TIMEOUT_MILLIS,
            "Voice end write timed out",
        )
    }

    private suspend fun handshake() {
        while (true) {
            val message = readMessage() ?: throw EOFException("TV closed before remote start")
            if (handle(message)) break
        }
        connection.socket.soTimeout = 0
    }

    private fun startReader() {
        readerJob = scope.launch(Dispatchers.IO) {
            var failure: Throwable? = null
            try {
                while (!closed.get()) {
                    val message = readMessage() ?: break
                    handle(message)
                }
            } catch (error: Throwable) {
                if (!closed.get()) failure = error
            } finally {
                if (!closed.getAndSet(true)) {
                    resetVoiceState(failure ?: EOFException("TV closed the remote connection"))
                    connection.socket.close()
                    onLost(failure)
                }
            }
        }
    }

    private suspend fun handle(message: RemoteMessage): Boolean {
        when {
            message.hasRemoteConfigure() -> {
                activeFeatures = negotiatedFeatures(message.remoteConfigure.code1)
                writer.send(
                    RemoteMessage.newBuilder()
                        .setRemoteConfigure(
                            RemoteConfigure.newBuilder()
                                .setCode1(activeFeatures)
                                .setDeviceInfo(
                                    RemoteDeviceInfo.newBuilder()
                                        .setUnknown1(1)
                                        .setUnknown2("1")
                                        .setPackageName("dev.local.androidtvremote")
                                        .setAppVersion("0.1.0"),
                                ),
                        ).build(),
                )
            }

            message.hasRemoteSetActive() -> writer.send(
                RemoteMessage.newBuilder()
                    .setRemoteSetActive(RemoteSetActive.newBuilder().setActive(activeFeatures))
                    .build(),
            )

            message.hasRemotePingRequest() -> writer.send(
                RemoteMessageFactory.pong(message.remotePingRequest.val1),
            )

            message.hasRemoteStart() -> {
                return true
            }

            message.hasRemoteVoiceBegin() -> voiceMutex.withLock {
                val waiter = pendingVoiceBegin
                if (waiter?.isActive == true && voiceGate.acceptBegin(message.remoteVoiceBegin.sessionId)) {
                    waiter.complete(message.remoteVoiceBegin.sessionId)
                }
            }
        }
        return false
    }

    private suspend fun readMessage(): RemoteMessage? = withContext(Dispatchers.IO) {
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation {
                runCatching { connection.socket.close() }
            }
            try {
                val message = frameReader.read(input)?.let(RemoteMessage::parseFrom)
                if (continuation.isActive) continuation.resume(message)
            } catch (error: Throwable) {
                if (continuation.isActive) continuation.resumeWithException(error)
            }
        }
    }

    suspend fun close() {
        val job = readerJob
        readerJob = null
        if (!closed.getAndSet(true)) {
            resetVoiceState(CancellationException("Remote session closed"))
            withContext(Dispatchers.IO) { runCatching { connection.socket.close() } }
        }
        job?.cancelAndJoin()
    }

    private suspend fun resetVoiceState(cause: Throwable) {
        voiceMutex.withLock {
            pendingVoiceBegin?.completeExceptionally(cause)
            pendingVoiceBegin = null
            voiceGate.reset()
        }
    }

    suspend fun closeAfterEndingLongPress(command: RemoteCommand?) {
        if (command == null) {
            close()
            return
        }
        coroutineScope {
            val endJob = launch(start = CoroutineStart.UNDISPATCHED) {
                runCatching { send(command, RemoteKeyAction.END_LONG) }
            }
            val endedBeforeTimeout = withTimeoutOrNull(END_LONG_CLOSE_TIMEOUT_MILLIS) {
                endJob.join()
                true
            } ?: false
            if (!endedBeforeTimeout) closeNow()
            endJob.cancelAndJoin()
        }
        close()
    }

    fun closeNow() {
        if (!closed.getAndSet(true)) runCatching { connection.socket.close() }
        readerJob?.cancel()
    }

    companion object {
        private const val FEATURE_PING = 1 shl 0
        private const val FEATURE_KEY = 1 shl 1
        internal const val FEATURE_VOICE = 1 shl 3
        private const val FEATURE_POWER = 1 shl 5
        private const val FEATURE_VOLUME = 1 shl 6
        internal const val CLIENT_FEATURES =
            FEATURE_PING or FEATURE_KEY or FEATURE_VOICE or FEATURE_POWER or FEATURE_VOLUME
        internal fun negotiatedFeatures(tvFeatures: Int): Int = CLIENT_FEATURES and tvFeatures
        private const val KEY_SEND_TIMEOUT_MILLIS = 500L
        private const val END_LONG_CLOSE_TIMEOUT_MILLIS = 500L
        private const val VOICE_BEGIN_TIMEOUT_MILLIS = 2_000L
        private const val VOICE_SEND_TIMEOUT_MILLIS = 1_000L

        suspend fun connect(
            host: String,
            expectedFingerprint: String?,
            tlsClient: TlsClient,
            scope: CoroutineScope,
            onLost: (Throwable?) -> Unit,
        ): RemoteSession {
            val connection = tlsClient.connectRemote(host, expectedFingerprint)
            val session = RemoteSession(connection, scope, onLost, DelimitedFrameReader())
            return try {
                session.handshake()
                session.startReader()
                session
            } catch (error: Throwable) {
                session.closeNow()
                throw error
            }
        }
    }
}

internal class VoiceSessionGate {
    private var waiting = false
    private var activeSessionId: Int? = null

    fun startWaiting() {
        check(!waiting && activeSessionId == null) { "Voice session is already active" }
        waiting = true
    }

    fun acceptBegin(sessionId: Int): Boolean {
        if (!waiting || activeSessionId != null) return false
        waiting = false
        activeSessionId = sessionId
        return true
    }

    fun cancelAndTakeActive(): Int? {
        waiting = false
        return activeSessionId.also { activeSessionId = null }
    }

    fun isActive(sessionId: Int): Boolean = activeSessionId == sessionId

    fun takeEnd(sessionId: Int): Boolean {
        if (activeSessionId != sessionId) return false
        activeSessionId = null
        return true
    }

    fun reset() {
        waiting = false
        activeSessionId = null
    }
}

private class SerializedWriter(
    private val output: OutputStream,
) {
    private val mutex = Mutex()

    suspend fun send(message: RemoteMessage) {
        val frame = Framing.frame(message.toByteArray())
        mutex.withLock {
            withContext(Dispatchers.IO) {
                output.write(frame)
                output.flush()
            }
        }
    }
}
