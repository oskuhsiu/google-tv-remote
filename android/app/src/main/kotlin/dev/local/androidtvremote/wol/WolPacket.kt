package dev.local.androidtvremote.wol

object WolPacket {
    const val DEFAULT_PORT = 9
    const val PACKET_LENGTH = 102

    fun parseMac(mac: String): ByteArray {
        val clean = mac.replace(":", "").replace("-", "").replace(".", "").replace(" ", "").trim()
        require(clean.length == 12) { "Invalid MAC address length" }
        require(clean.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }) {
            "MAC address must contain only hexadecimal characters"
        }
        val bytes = ByteArray(6)
        for (i in 0 until 6) {
            val byteStr = clean.substring(i * 2, i * 2 + 2)
            bytes[i] = byteStr.toInt(16).toByte()
        }
        return bytes
    }

    fun isValidMac(mac: String?): Boolean {
        if (mac.isNullOrBlank()) return false
        val clean = mac.replace(":", "").replace("-", "").replace(".", "").replace(" ", "").trim()
        if (clean.length != 12) return false
        if (!clean.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }) return false
        val bytes = try {
            parseMac(mac)
        } catch (_: Throwable) {
            return false
        }
        // Disallow all zeros or all 0xFF (broadcast)
        if (bytes.all { it == 0.toByte() } || bytes.all { it == 0xFF.toByte() }) return false
        // Disallow multicast (least significant bit of first octet is 1)
        if ((bytes[0].toInt() and 0x01) != 0) return false
        return true
    }

    fun formatMac(mac: String): String {
        val bytes = parseMac(mac)
        return bytes.joinToString(":") { "%02X".format(it) }
    }

    fun buildMagicPacket(macBytes: ByteArray): ByteArray {
        require(macBytes.size == 6) { "MAC address must be 6 bytes" }
        val packet = ByteArray(PACKET_LENGTH)
        // 6 bytes of 0xFF
        for (i in 0 until 6) {
            packet[i] = 0xFF.toByte()
        }
        // 16 repetitions of the target MAC
        for (i in 0 until 16) {
            System.arraycopy(macBytes, 0, packet, 6 + i * 6, 6)
        }
        return packet
    }

    fun verifyMagicPacket(packet: ByteArray, macBytes: ByteArray): Boolean {
        if (packet.size != PACKET_LENGTH || macBytes.size != 6) return false
        for (i in 0 until 6) {
            if (packet[i] != 0xFF.toByte()) return false
        }
        for (i in 0 until 16) {
            for (j in 0 until 6) {
                if (packet[6 + i * 6 + j] != macBytes[j]) return false
            }
        }
        return true
    }
}
