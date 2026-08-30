package dev.local.androidtvremote.ui

import dev.local.androidtvremote.RemoteCommand
import dev.local.androidtvremote.RemoteKeyAction
import dev.local.androidtvremote.RemotePressBehavior
import dev.local.androidtvremote.RemotePressPolicy
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal class RemotePressHandler(
    private val nowMillis: () -> Long = { System.nanoTime() / 1_000_000L },
    private val send: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
) {
    suspend fun press(
        command: RemoteCommand,
        awaitRelease: suspend () -> Boolean,
        onLongPress: () -> Unit = {},
    ) {
        when (RemotePressPolicy.behaviorFor(command)) {
            RemotePressBehavior.SINGLE -> {
                send(command, RemoteKeyAction.SHORT)
                awaitRelease()
            }

            RemotePressBehavior.REPEAT -> repeatWhilePressed(command, awaitRelease)
            RemotePressBehavior.LONG_PRESS -> longPress(command, awaitRelease, onLongPress)
        }
    }

    private suspend fun repeatWhilePressed(
        command: RemoteCommand,
        awaitRelease: suspend () -> Boolean,
    ) = coroutineScope {
        val repeatJob = launch(start = CoroutineStart.UNDISPATCHED) {
            val pressedAtMillis = nowMillis()
            send(command, RemoteKeyAction.SHORT)
            var nextRepeatAtMillis = pressedAtMillis + RemotePressPolicy.REPEAT_DELAY_MILLIS
            while (isActive) {
                val waitMillis = nextRepeatAtMillis - nowMillis()
                if (waitMillis > 0) delay(waitMillis)
                send(command, RemoteKeyAction.SHORT)
                nextRepeatAtMillis += RemotePressPolicy.REPEAT_INTERVAL_MILLIS
                val completedAtMillis = nowMillis()
                while (nextRepeatAtMillis <= completedAtMillis) {
                    nextRepeatAtMillis += RemotePressPolicy.REPEAT_INTERVAL_MILLIS
                }
            }
        }
        try {
            awaitRelease()
        } finally {
            withContext(NonCancellable) { repeatJob.cancelAndJoin() }
        }
    }

    private suspend fun longPress(
        command: RemoteCommand,
        awaitRelease: suspend () -> Boolean,
        onLongPress: () -> Unit,
    ) = coroutineScope {
        val pressedAtMillis = nowMillis()
        var longStarted = false
        var longStartAttempted = false
        val longJob = launch {
            delay(RemotePressPolicy.LONG_PRESS_MILLIS)
            withContext(NonCancellable) {
                longStartAttempted = true
                send(command, RemoteKeyAction.START_LONG)
                longStarted = true
                runCatching(onLongPress)
            }
        }
        var released = false
        var completedAtMillis: Long? = null
        try {
            released = awaitRelease()
            completedAtMillis = nowMillis()
        } catch (error: Throwable) {
            completedAtMillis = nowMillis()
            throw error
        } finally {
            withContext(NonCancellable) {
                longJob.cancelAndJoin()
                val thresholdReached = checkNotNull(completedAtMillis) - pressedAtMillis >=
                    RemotePressPolicy.LONG_PRESS_MILLIS
                if (!longStarted && !longStartAttempted && thresholdReached) {
                    longStartAttempted = true
                    send(command, RemoteKeyAction.START_LONG)
                    longStarted = true
                    runCatching(onLongPress)
                }
                if (longStarted) send(command, RemoteKeyAction.END_LONG)
            }
        }
        if (!longStarted && released) send(command, RemoteKeyAction.SHORT)
    }
}
