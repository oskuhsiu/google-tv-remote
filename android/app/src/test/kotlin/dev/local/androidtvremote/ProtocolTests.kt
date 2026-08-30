package dev.local.androidtvremote

import dev.local.androidtvremote.protocol.DelimitedFrameReader
import dev.local.androidtvremote.protocol.FrameException
import dev.local.androidtvremote.protocol.Framing
import dev.local.androidtvremote.protocol.OversizedFrameException
import dev.local.androidtvremote.protocol.PairingCode
import dev.local.androidtvremote.protocol.PairingSecret
import dev.local.androidtvremote.protocol.RemoteMessageFactory
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
