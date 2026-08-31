package dev.local.androidtvremote

import dev.local.androidtvremote.protocol.DelimitedFrameReader
import dev.local.androidtvremote.protocol.FrameException
import dev.local.androidtvremote.protocol.Framing
import dev.local.androidtvremote.protocol.OversizedFrameException
import dev.local.androidtvremote.protocol.PairingCode
import dev.local.androidtvremote.protocol.PairingSecret
import dev.local.androidtvremote.protocol.RemoteMessageFactory
import dev.local.androidtvremote.protocol.RemoteSession
import dev.local.androidtvremote.protocol.VoiceSessionGate
import dev.local.androidtvremote.audio.PcmChunkAccumulator
import java.io.ByteArrayInputStream
import java.io.EOFException
import java.math.BigInteger
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import remote.Remotemessage.RemoteDirection

class ProtocolTests {
    @Test
    fun `pairing code normalizes lowercase and rejects malformed values`() {
        assertEquals("ABCDEF", PairingCode.parse("  abcdef ")?.value)
        assertNull(PairingCode.parse("12345"))
        assertNull(PairingCode.parse("1234567"))
        assertNull(PairingCode.parse("12G456"))
    }

    @Test
    fun `pairing secret matches pinned reference vector`() {
        val secret = PairingSecret.calculate(
            clientModulus = BigInteger("A1B2C3D4", 16),
            clientExponent = BigInteger.valueOf(65_537),
            serverModulus = BigInteger("FEDCBA98", 16),
            serverExponent = BigInteger.valueOf(65_537),
            code = PairingCode.parse("82BEEF")!!,
        )

        assertEquals(
            "822F426E6F8A86ED86B11B408812D9E3815319E968C438EBC83142CEC6A94169",
            secret.joinToString("") { "%02X".format(it) },
        )
        assertThrows(IllegalArgumentException::class.java) {
            PairingSecret.calculate(
                BigInteger("A1B2C3D4", 16),
                BigInteger.valueOf(65_537),
                BigInteger("FEDCBA98", 16),
                BigInteger.valueOf(65_537),
                PairingCode.parse("00BEEF")!!,
            )
        }
    }

    @Test
    fun `all app commands serialize as short key injections`() {
        RemoteCommand.entries.forEach { command ->
            val message = RemoteMessageFactory.key(command)
            assertEquals(command.keyCode, message.remoteKeyInject.keyCodeValue)
            assertEquals(RemoteDirection.SHORT, message.remoteKeyInject.direction)
        }
    }

    @Test
    fun `all remote key actions map to their protobuf directions`() {
        val expected = mapOf(
            RemoteKeyAction.SHORT to RemoteDirection.SHORT,
            RemoteKeyAction.START_LONG to RemoteDirection.START_LONG,
            RemoteKeyAction.END_LONG to RemoteDirection.END_LONG,
        )

        expected.forEach { (action, direction) ->
            assertEquals(direction, RemoteMessageFactory.key(RemoteCommand.SELECT, action).remoteKeyInject.direction)
        }
    }

    @Test
    fun `long protocol actions are rejected for non select commands`() {
        assertThrows(IllegalArgumentException::class.java) {
            RemoteMessageFactory.key(RemoteCommand.UP, RemoteKeyAction.START_LONG)
        }
        assertThrows(IllegalArgumentException::class.java) {
            RemoteMessageFactory.key(RemoteCommand.VOLUME_UP, RemoteKeyAction.END_LONG)
        }
    }

    @Test
    fun `ping response echoes request value`() {
        assertEquals(73, RemoteMessageFactory.pong(73).remotePingResponse.val1)
    }

    @Test
    fun `voice messages serialize search begin payload and end with one session id`() {
        val sessionId = 417
        val samples = ByteArray(8_192) { (it % 251).toByte() }

        val search = RemoteMessageFactory.search()
        val begin = RemoteMessageFactory.voiceBegin(sessionId)
        val payload = RemoteMessageFactory.voicePayload(sessionId, samples)
        val end = RemoteMessageFactory.voiceEnd(sessionId)

        assertEquals(RemoteMessageFactory.VOICE_SEARCH_KEY_CODE, search.remoteKeyInject.keyCodeValue)
        assertEquals(RemoteDirection.SHORT, search.remoteKeyInject.direction)
        assertEquals(sessionId, begin.remoteVoiceBegin.sessionId)
        assertEquals(sessionId, payload.remoteVoicePayload.sessionId)
        assertArrayEquals(samples, payload.remoteVoicePayload.samples.toByteArray())
        assertEquals(sessionId, end.remoteVoiceEnd.sessionId)
    }

    @Test
    fun `voice feature is advertised and negotiated only when the TV supports it`() {
        assertEquals(
            RemoteSession.FEATURE_VOICE,
            RemoteSession.negotiatedFeatures(RemoteSession.FEATURE_VOICE) and RemoteSession.FEATURE_VOICE,
        )
        assertEquals(0, RemoteSession.negotiatedFeatures(0) and RemoteSession.FEATURE_VOICE)
    }

    @Test
    fun `runtime microphone revocation maps to permission denied`() {
        assertEquals(RemoteError.VOICE_PERMISSION_DENIED, voiceFailureError(SecurityException()))
        assertEquals(RemoteError.VOICE_SESSION_FAILED, voiceFailureError(IllegalStateException()))
    }

    @Test
    fun `voice gate ignores stale begin and sends end at most once`() {
        val gate = VoiceSessionGate()
        assertEquals(false, gate.acceptBegin(10))
        gate.startWaiting()
        assertEquals(true, gate.acceptBegin(11))
        assertEquals(false, gate.acceptBegin(12))
        assertEquals(true, gate.isActive(11))
        assertEquals(false, gate.takeEnd(12))
        assertEquals(true, gate.takeEnd(11))
        assertEquals(false, gate.takeEnd(11))

        gate.startWaiting()
        assertNull(gate.cancelAndTakeActive())
        assertEquals(false, gate.acceptBegin(13))

        gate.startWaiting()
        assertEquals(true, gate.acceptBegin(14))
        assertEquals(14, gate.cancelAndTakeActive())
        gate.startWaiting()
        assertNull(gate.cancelAndTakeActive())
    }

    @Test
    fun `pcm accumulator emits 8 KiB chunks and zero pads its tail`() {
        val accumulator = PcmChunkAccumulator()
        val first = ByteArray(5_000) { 1 }
        val second = ByteArray(4_000) { 2 }

        assertEquals(0, accumulator.append(first).size)
        val chunks = accumulator.append(second)
        assertEquals(1, chunks.size)
        assertEquals(8_192, chunks.single().size)
        assertEquals(1, chunks.single()[4_999].toInt())
        assertEquals(2, chunks.single()[5_000].toInt())

        val tail = checkNotNull(accumulator.finish())
        assertEquals(8_192, tail.size)
        assertEquals(2, tail[807].toInt())
        assertEquals(0, tail[808].toInt())
        assertNull(accumulator.finish())
    }

    @Test
    fun `bounded reader accepts exactly one mebibyte`() {
        val payload = ByteArray(DelimitedFrameReader.DEFAULT_MAX_FRAME_SIZE) { (it % 251).toByte() }
        val framed = Framing.frame(payload)

        assertArrayEquals(payload, DelimitedFrameReader().read(ByteArrayInputStream(framed)))
    }

    @Test
    fun `bounded reader rejects oversize malformed and truncated frames`() {
        val reader = DelimitedFrameReader()
        val oversize = Framing.encodeLength(DelimitedFrameReader.DEFAULT_MAX_FRAME_SIZE + 1)
        assertThrows(OversizedFrameException::class.java) {
            reader.read(ByteArrayInputStream(oversize))
        }
        assertThrows(FrameException::class.java) {
            reader.read(ByteArrayInputStream(byteArrayOf(0x80.toByte(), 0x80.toByte(), 0x80.toByte(), 0x80.toByte(), 0x80.toByte(), 0x00)))
        }
        assertThrows(EOFException::class.java) {
            reader.read(ByteArrayInputStream(byteArrayOf(0x03, 0x01)))
        }
    }
}
