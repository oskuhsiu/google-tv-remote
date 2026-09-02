package dev.local.androidtvremote

import dev.local.androidtvremote.wol.DefaultWolSender
import dev.local.androidtvremote.wol.WolPacket
import java.net.InetAddress
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WolTests {

    @Test
    fun `mac validation accepts standard colon hyphen and plain hex`() {
        assertTrue(WolPacket.isValidMac("A4:77:33:12:AB:CD"))
        assertTrue(WolPacket.isValidMac("a4:77:33:12:ab:cd"))
        assertTrue(WolPacket.isValidMac("A4-77-33-12-AB-CD"))
        assertTrue(WolPacket.isValidMac("a4-77-33-12-ab-cd"))
        assertTrue(WolPacket.isValidMac("A4773312ABCD"))
        assertTrue(WolPacket.isValidMac("a4773312abcd"))
        assertTrue(WolPacket.isValidMac("  a4:77:33:12:ab:cd  "))
    }

    @Test
    fun `mac validation rejects malformed blank multicast and reserved addresses`() {
        assertFalse(WolPacket.isValidMac(null))
        assertFalse(WolPacket.isValidMac(""))
        assertFalse(WolPacket.isValidMac("   "))
        assertFalse(WolPacket.isValidMac("A4:77:33:12:AB"))
        assertFalse(WolPacket.isValidMac("A4:77:33:12:AB:CD:EF"))
        assertFalse(WolPacket.isValidMac("A4:77:33:12:AB:CG"))
        assertFalse(WolPacket.isValidMac("00:00:00:00:00:00"))
        assertFalse(WolPacket.isValidMac("FF:FF:FF:FF:FF:FF"))
        assertFalse(WolPacket.isValidMac("01:00:5E:00:00:01")) // Multicast bit set
    }

    @Test
    fun `mac formatting normalizes to uppercase colon separated`() {
        assertEquals("A4:77:33:12:AB:CD", WolPacket.formatMac("a4773312abcd"))
        assertEquals("A4:77:33:12:AB:CD", WolPacket.formatMac("a4-77-33-12-ab-cd"))
        assertEquals("A4:77:33:12:AB:CD", WolPacket.formatMac("  a4:77:33:12:ab:cd  "))
    }

    @Test
    fun `magic packet contains six FF prefix followed by sixteen repetitions of target mac`() {
        val mac = "A4:77:33:12:AB:CD"
        val macBytes = WolPacket.parseMac(mac)
        val packet = WolPacket.buildMagicPacket(macBytes)

        assertEquals(102, packet.size)

        // First 6 bytes must be 0xFF
        for (i in 0 until 6) {
            assertEquals(0xFF.toByte(), packet[i])
        }

        // Subsequent 16 * 6 bytes must match target MAC repeated 16 times
        for (rep in 0 until 16) {
            for (byteIndex in 0 until 6) {
                assertEquals(
                    macBytes[byteIndex],
                    packet[6 + rep * 6 + byteIndex],
                )
            }
        }

        assertTrue(WolPacket.verifyMagicPacket(packet, macBytes))

        // Corrupted packet verification
        val corrupted = packet.copyOf()
        corrupted[10] = (corrupted[10].toInt() xor 0xFF).toByte()
        assertFalse(WolPacket.verifyMagicPacket(corrupted, macBytes))
    }

    @Test
    fun `wol sender transmits packets to provided broadcast destination`() = runBlocking {
        val sender = DefaultWolSender(
            broadcastProvider = { listOf(InetAddress.getByName("127.0.0.1")) },
        )
        val result = sender.send(
            macAddress = "A4:77:33:12:AB:CD",
            targetHost = "127.0.0.1",
            port = 19999,
            repeatCount = 1,
            repeatDelayMillis = 0L,
        )
        assertTrue(result)
    }

    @Test
    fun `wol sender returns false for invalid mac address`() = runBlocking {
        val sender = DefaultWolSender()
        val result = sender.send(macAddress = "invalid")
        assertFalse(result)
    }

    @Test
    fun `tv device and last tv record preserve mac address`() {
        val device = TvDevice(
            id = "test-id",
            name = "Test TV",
            source = TvSource.MANUAL,
            macAddress = "A4:77:33:12:AB:CD",
        )
        assertEquals("A4:77:33:12:AB:CD", device.macAddress)

        val record = LastTvRecord(
            device = device,
            lastHost = "192.168.1.50",
            bonjourLocatorKey = null,
            lastConnectedAt = 123456789L,
            clientIdentityFingerprint = "client-fp",
            pairingPeerFingerprint = "pairing-fp",
            remotePeerFingerprint = "test-id",
            macAddress = "A4:77:33:12:AB:CD",
        )
        assertEquals("A4:77:33:12:AB:CD", record.macAddress)
    }

    @Test
    fun `mac validation accepts dot and space separated notation`() {
        assertTrue(WolPacket.isValidMac("a477.3312.abcd"))
        assertTrue(WolPacket.isValidMac("A4 77 33 12 AB CD"))
        assertEquals("A4:77:33:12:AB:CD", WolPacket.formatMac("a477.3312.abcd"))
        assertEquals("A4:77:33:12:AB:CD", WolPacket.formatMac("A4 77 33 12 AB CD"))
    }

    @Test
    fun `arp table parser extracts matching mac address`() {
        val arpLines = sequenceOf(
            "IP address       HW type     Flags       HW address            Mask     Device",
            "192.168.1.1     0x1         0x2         00:11:22:33:44:55     *        wlan0",
            "192.168.1.50    0x1         0x2         a4:77:33:12:ab:cd     *        wlan0",
            "192.168.1.99    0x1         0x0         00:00:00:00:00:00     *        wlan0",
        )
        val mac = dev.local.androidtvremote.wol.DefaultMacDiscoverer.parseArpTable(arpLines, "192.168.1.50")
        assertEquals("A4:77:33:12:AB:CD", mac)

        val nonExistent = dev.local.androidtvremote.wol.DefaultMacDiscoverer.parseArpTable(arpLines, "192.168.1.200")
        assertEquals(null, nonExistent)

        val incomplete = dev.local.androidtvremote.wol.DefaultMacDiscoverer.parseArpTable(arpLines, "192.168.1.99")
        assertEquals(null, incomplete)
    }

    @Test
    fun `wol sender transmits valid magic packet payload over datagram socket`() = runBlocking {
        val serverSocket = java.net.DatagramSocket(0, InetAddress.getByName("127.0.0.1"))
        val boundPort = serverSocket.localPort
        serverSocket.soTimeout = 2000

        try {
            val sender = DefaultWolSender(
                broadcastProvider = { listOf(InetAddress.getByName("127.0.0.1")) },
            )
            val mac = "A4:77:33:12:AB:CD"
            val sent = sender.send(
                macAddress = mac,
                targetHost = null,
                port = boundPort,
                repeatCount = 1,
                repeatDelayMillis = 0L,
            )
            assertTrue(sent)

            val receiveBuffer = ByteArray(256)
            val packet = java.net.DatagramPacket(receiveBuffer, receiveBuffer.size)
            serverSocket.receive(packet)

            val expectedBytes = WolPacket.parseMac(mac)
            assertTrue(WolPacket.verifyMagicPacket(packet.data.copyOf(packet.length), expectedBytes))
        } finally {
            serverSocket.close()
        }
    }

    @Test
    fun `legacy record without mac address defaults to null`() {
        val device = TvDevice(
            id = "test-id",
            name = "Test TV",
            source = TvSource.DISCOVERY,
        )
        assertEquals(null, device.macAddress)

        val record = LastTvRecord(
            device = device,
            lastHost = "192.168.1.50",
            bonjourLocatorKey = "locator-1",
            lastConnectedAt = 100L,
            clientIdentityFingerprint = "c-fp",
            pairingPeerFingerprint = "p-fp",
            remotePeerFingerprint = "test-id",
        )
        assertEquals(null, record.macAddress)
    }
}
