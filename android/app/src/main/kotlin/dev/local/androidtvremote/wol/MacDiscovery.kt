package dev.local.androidtvremote.wol

import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

interface MacAddressDiscoverer {
    suspend fun discoverMac(host: String): String?
}

class DefaultMacDiscoverer : MacAddressDiscoverer {
    override suspend fun discoverMac(host: String): String? = withContext(Dispatchers.IO) {
        // Opportunistic lookup in /proc/net/arp (best effort on supported/older devices)
        runCatching {
            val arp = File("/proc/net/arp")
            if (!arp.canRead()) return@runCatching null
            arp.useLines { lines -> parseArpTable(lines, host) }
        }.getOrNull()
    }

    companion object {
        fun parseArpTable(lines: Sequence<String>, host: String): String? {
            for (line in lines) {
                val parts = line.trim().split("\\s+".toRegex())
                if (parts.size >= 4 && parts[0] == host) {
                    val mac = parts[3]
                    if (WolPacket.isValidMac(mac)) {
                        return WolPacket.formatMac(mac)
                    }
                }
            }
            return null
        }
    }
}
