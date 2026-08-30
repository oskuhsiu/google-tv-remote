package dev.local.androidtvremote

import dev.local.androidtvremote.ui.RemotePressHandler
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RemotePressHandlerTests {
    @Test
    fun `quick select emits one short action`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }

        handler.press(RemoteCommand.SELECT, awaitRelease = {
            delay(RemotePressPolicy.LONG_PRESS_MILLIS - 1)
            true
        })

        assertEquals(listOf(RemoteKeyAction.SHORT), events)
    }

    @Test
    fun `held select emits start then end without a short action`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        var longFeedbackCount = 0
        val handler = pressHandler { _, action -> events += action }

        handler.press(
            command = RemoteCommand.SELECT,
            awaitRelease = {
                delay(RemotePressPolicy.LONG_PRESS_MILLIS + 50)
                true
            },
            onLongPress = { longFeedbackCount += 1 },
        )

        assertEquals(
            listOf(RemoteKeyAction.START_LONG, RemoteKeyAction.END_LONG),
            events,
        )
        assertEquals(1, longFeedbackCount)
    }

    @Test
    fun `select released at the exact threshold is a long press`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }

        handler.press(RemoteCommand.SELECT, awaitRelease = {
            delay(RemotePressPolicy.LONG_PRESS_MILLIS)
            true
        })

        assertEquals(
            listOf(RemoteKeyAction.START_LONG, RemoteKeyAction.END_LONG),
            events,
        )
    }

    @Test
    fun `select cancelled at the exact threshold still balances long actions`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }

        handler.press(RemoteCommand.SELECT, awaitRelease = {
            delay(RemotePressPolicy.LONG_PRESS_MILLIS)
            false
        })

        assertEquals(
            listOf(RemoteKeyAction.START_LONG, RemoteKeyAction.END_LONG),
            events,
        )
    }

    @Test
    fun `cancelled long select still releases the active key`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }

        handler.press(RemoteCommand.SELECT, awaitRelease = {
            delay(RemotePressPolicy.LONG_PRESS_MILLIS + 50)
            false
        })

        assertEquals(
            listOf(RemoteKeyAction.START_LONG, RemoteKeyAction.END_LONG),
            events,
        )
    }

    @Test
    fun `coroutine cancellation before threshold emits nothing`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }
        val pressJob = launch {
            handler.press(RemoteCommand.SELECT, awaitRelease = { awaitCancellation() })
        }

        runCurrent()
        advanceTimeBy(RemotePressPolicy.LONG_PRESS_MILLIS - 1)
        pressJob.cancelAndJoin()

        assertEquals(emptyList<RemoteKeyAction>(), events)
    }

    @Test
    fun `coroutine cancellation after threshold ends the active select`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }
        val pressJob = launch {
            handler.press(RemoteCommand.SELECT, awaitRelease = { awaitCancellation() })
        }

        runCurrent()
        advanceTimeBy(RemotePressPolicy.LONG_PRESS_MILLIS)
        runCurrent()
        pressJob.cancelAndJoin()

        assertEquals(
            listOf(RemoteKeyAction.START_LONG, RemoteKeyAction.END_LONG),
            events,
        )
    }

    @Test
    fun `failed long start does not emit end or feedback`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val expected = IllegalStateException("send failed")
        var longFeedbackCount = 0
        val handler = pressHandler { _, action ->
            events += action
            if (action == RemoteKeyAction.START_LONG) throw expected
        }

        val actual = runCatching {
            handler.press(
                command = RemoteCommand.SELECT,
                awaitRelease = {
                    delay(RemotePressPolicy.LONG_PRESS_MILLIS + 1)
                    true
                },
                onLongPress = { longFeedbackCount += 1 },
            )
        }.exceptionOrNull()

        assertTrue(actual is IllegalStateException)
        assertEquals(expected.message, actual?.message)
        assertEquals(listOf(RemoteKeyAction.START_LONG), events)
        assertEquals(0, longFeedbackCount)
    }

    @Test
    fun `repeatable key sends immediately then repeats until release with no touch-up action`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }

        handler.press(RemoteCommand.UP, awaitRelease = {
            delay(
                RemotePressPolicy.REPEAT_DELAY_MILLIS +
                    RemotePressPolicy.REPEAT_INTERVAL_MILLIS * 2 +
                    RemotePressPolicy.REPEAT_INTERVAL_MILLIS / 2,
            )
            true
        })

        assertEquals(List(4) { RemoteKeyAction.SHORT }, events)
    }

    @Test
    fun `repeatable key released before delay sends only once`() = runTest {
        val events = mutableListOf<RemoteKeyAction>()
        val handler = pressHandler { _, action -> events += action }

        handler.press(RemoteCommand.VOLUME_DOWN, awaitRelease = {
            delay(RemotePressPolicy.REPEAT_DELAY_MILLIS - 1)
            true
        })

        assertEquals(listOf(RemoteKeyAction.SHORT), events)
    }

    @Test
    fun `initial send latency does not move the repeat schedule`() = runTest {
        val sendTimes = mutableListOf<Long>()
        var firstSend = true
        val handler = pressHandler { _, _ ->
            sendTimes += testScheduler.currentTime
            if (firstSend) {
                firstSend = false
                delay(150)
            }
        }

        handler.press(RemoteCommand.UP, awaitRelease = {
            delay(650)
            true
        })

        assertEquals(listOf(0L, 400L, 500L, 600L), sendTimes)
    }

    @Test
    fun `slow repeat skips missed ticks but stays on the press down grid`() = runTest {
        val sendTimes = mutableListOf<Long>()
        val handler = pressHandler { _, _ ->
            sendTimes += testScheduler.currentTime
            if (sendTimes.size == 2) delay(250)
        }

        handler.press(RemoteCommand.DOWN, awaitRelease = {
            delay(750)
            true
        })

        assertEquals(listOf(0L, 400L, 700L), sendTimes)
    }

    @Test
    fun `release cancels an in flight repeat without queuing another`() = runTest {
        val secondSendStarted = CompletableDeferred<Unit>()
        val blockSecondSend = CompletableDeferred<Unit>()
        val released = CompletableDeferred<Boolean>()
        var sendCount = 0
        val handler = pressHandler { _, _ ->
            sendCount += 1
            if (sendCount == 2) {
                secondSendStarted.complete(Unit)
                blockSecondSend.await()
            }
        }
        val pressJob = launch {
            handler.press(RemoteCommand.VOLUME_UP, awaitRelease = { released.await() })
        }

        runCurrent()
        advanceTimeBy(RemotePressPolicy.REPEAT_DELAY_MILLIS)
        runCurrent()
        secondSendStarted.await()
        released.complete(true)
        pressJob.join()
        advanceTimeBy(RemotePressPolicy.REPEAT_INTERVAL_MILLIS * 3)
        runCurrent()

        assertEquals(2, sendCount)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
private fun TestScope.pressHandler(
    send: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
): RemotePressHandler = RemotePressHandler(
    nowMillis = { testScheduler.currentTime },
    send = send,
)
