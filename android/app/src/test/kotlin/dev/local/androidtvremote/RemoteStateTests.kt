package dev.local.androidtvremote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteStateTests {
    @Test
    fun `v1 exposes exactly twelve commands and no play pause`() {
        assertEquals(12, RemoteCommand.entries.size)
        assertFalse(RemoteCommand.entries.any { "PLAY" in it.name || "PAUSE" in it.name })
        assertEquals(
            mapOf(
                "UP" to 19,
                "DOWN" to 20,
                "LEFT" to 21,
                "RIGHT" to 22,
                "SELECT" to 23,
                "BACK" to 4,
                "HOME" to 3,
                "MENU" to 82,
                "POWER" to 26,
                "VOLUME_UP" to 24,
                "VOLUME_DOWN" to 25,
                "MUTE" to 164,
            ),
            RemoteCommand.entries.associate { it.name to it.keyCode },
        )
    }

    @Test
    fun `press policy classifies long repeat and single commands`() {
        assertEquals(RemotePressBehavior.LONG_PRESS, RemotePressPolicy.behaviorFor(RemoteCommand.SELECT))
        assertEquals(
            setOf(
                RemoteCommand.UP,
                RemoteCommand.DOWN,
                RemoteCommand.LEFT,
                RemoteCommand.RIGHT,
                RemoteCommand.VOLUME_UP,
                RemoteCommand.VOLUME_DOWN,
            ),
            RemoteCommand.entries
                .filter { RemotePressPolicy.behaviorFor(it) == RemotePressBehavior.REPEAT }
                .toSet(),
        )
        assertEquals(
            setOf(RemoteCommand.BACK, RemoteCommand.HOME, RemoteCommand.MENU, RemoteCommand.POWER, RemoteCommand.MUTE),
            RemoteCommand.entries
                .filter { RemotePressPolicy.behaviorFor(it) == RemotePressBehavior.SINGLE }
                .toSet(),
        )
    }

    @Test
    fun `press timing constants are exact`() {
        assertEquals(400L, RemotePressPolicy.LONG_PRESS_MILLIS)
        assertEquals(400L, RemotePressPolicy.REPEAT_DELAY_MILLIS)
        assertEquals(100L, RemotePressPolicy.REPEAT_INTERVAL_MILLIS)
    }

    @Test
    fun `retry policy is bounded at one two four seconds`() {
        assertEquals(1_000L, RetryPolicy.delayMillis(1))
        assertEquals(2_000L, RetryPolicy.delayMillis(2))
        assertEquals(4_000L, RetryPolicy.delayMillis(3))
        assertNull(RetryPolicy.delayMillis(4))
    }

    @Test
    fun `remembered tuple is accepted only when every trust field matches`() {
        val record = LastTvRecord(
            device = TvDevice("remote-pin", "Living Room TV", TvSource.MANUAL),
            lastHost = "192.168.1.25",
            bonjourLocatorKey = null,
            lastConnectedAt = 42L,
            clientIdentityFingerprint = "client-pin",
            pairingPeerFingerprint = "pairing-pin",
            remotePeerFingerprint = "remote-pin",
        )

        assertTrue(TrustTupleValidator.isComplete(record, "client-pin"))
        assertFalse(TrustTupleValidator.isComplete(record.copy(lastHost = ""), "client-pin"))
        assertFalse(TrustTupleValidator.isComplete(record.copy(pairingPeerFingerprint = ""), "client-pin"))
        assertFalse(TrustTupleValidator.isComplete(record.copy(remotePeerFingerprint = "other"), "client-pin"))
        assertFalse(TrustTupleValidator.isComplete(record, "new-client-pin"))
    }

    @Test
    fun `foreground connects a valid remembered pairing without discovery`() {
        assertEquals(
            ForegroundAction.CONNECT_REMEMBERED,
            ForegroundPolicy.action(alreadyForeground = false, hasValidPairing = true),
        )
    }

    @Test
    fun `foreground discovers only without a valid remembered pairing`() {
        assertEquals(
            ForegroundAction.START_DISCOVERY,
            ForegroundPolicy.action(alreadyForeground = false, hasValidPairing = false),
        )
    }

    @Test
    fun `duplicate foreground entry is idempotent`() {
        assertEquals(
            ForegroundAction.NONE,
            ForegroundPolicy.action(alreadyForeground = true, hasValidPairing = true),
        )
        assertEquals(
            ForegroundAction.NONE,
            ForegroundPolicy.action(alreadyForeground = true, hasValidPairing = false),
        )
    }

    @Test
    fun `automatic discovery requires foreground without a valid pairing`() {
        assertTrue(ForegroundPolicy.allowsAutomaticDiscovery(isForeground = true, hasValidPairing = false))
        assertFalse(ForegroundPolicy.allowsAutomaticDiscovery(isForeground = false, hasValidPairing = false))
        assertFalse(ForegroundPolicy.allowsAutomaticDiscovery(isForeground = true, hasValidPairing = true))
        assertFalse(ForegroundPolicy.allowsAutomaticDiscovery(isForeground = false, hasValidPairing = true))
    }
}
