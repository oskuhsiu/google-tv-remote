package dev.local.androidtvremote.wol

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

interface WolPacketSender {
    suspend fun send(
        macAddress: String,
        targetHost: String? = null,
        port: Int = WolPacket.DEFAULT_PORT,
        repeatCount: Int = 3,
        repeatDelayMillis: Long = 50L,
    ): Boolean
}

class DefaultWolSender(
    private val broadcastProvider: () -> List<InetAddress> = ::discoverBroadcastAddresses,
) : WolPacketSender {

    override suspend fun send(
        macAddress: String,
        targetHost: String?,
        port: Int,
        repeatCount: Int,
        repeatDelayMillis: Long,
    ): Boolean = withContext(Dispatchers.IO) {
        val macBytes = runCatching { WolPacket.parseMac(macAddress) }.getOrNull() ?: return@withContext false
        val packetData = WolPacket.buildMagicPacket(macBytes)

        val destinations = mutableSetOf<InetAddress>()
        destinations.addAll(broadcastProvider())
        runCatching { destinations.add(InetAddress.getByName("255.255.255.255")) }

        if (!targetHost.isNullOrBlank()) {
            runCatching {
                val targetAddr = InetAddress.getByName(targetHost)
                destinations.add(targetAddr)
            }
        }

        var anySent = false
        runCatching {
            DatagramSocket().use { socket ->
                socket.broadcast = true
                for (attempt in 0 until repeatCount.coerceAtLeast(1)) {
                    if (attempt > 0 && repeatDelayMillis > 0) {
                        delay(repeatDelayMillis)
                    }
                    for (dest in destinations) {
                        runCatching {
                            val datagram = DatagramPacket(packetData, packetData.size, dest, port)
                            socket.send(datagram)
                            anySent = true
                        }
                    }
                }
            }
        }
        anySent
    }

    companion object {
        fun discoverBroadcastAddresses(): List<InetAddress> {
            val broadcasts = mutableListOf<InetAddress>()
            val interfaces = runCatching { NetworkInterface.getNetworkInterfaces() }.getOrNull() ?: return broadcasts
            for (networkInterface in interfaces.asSequence()) {
                runCatching {
                    if (networkInterface.isLoopback || !networkInterface.isUp) return@runCatching
                    for (interfaceAddress in networkInterface.interfaceAddresses) {
                        val broadcast = interfaceAddress.broadcast
                        if (broadcast != null) {
                            broadcasts.add(broadcast)
                        }
                    }
                }
            }
            return broadcasts
        }
    }
}
