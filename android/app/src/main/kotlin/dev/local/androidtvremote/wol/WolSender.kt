package dev.local.androidtvremote.wol

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import kotlinx.coroutines.CancellationException
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

data class NetworkInterfaceDetails(
    val name: String,
    val isLoopback: Boolean = false,
    val isUp: Boolean = true,
    val isVirtual: Boolean = false,
)

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

        val destinations = broadcastProvider()
        if (destinations.isEmpty()) {
            return@withContext false
        }

        var anySent = false
        try {
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
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Socket initialization / configuration error
        }
        anySent
    }

    companion object {
        private val EXCLUDED_INTERFACE_PREFIXES = listOf(
            "tun", "tap", "ppp", "p2p", "dummy", "rmnet", "ccmni", "sit", "ip6tnl"
        )

        fun isEligibleInterface(details: NetworkInterfaceDetails): Boolean {
            if (details.isLoopback || !details.isUp || details.isVirtual) {
                return false
            }
            val lower = details.name.lowercase()
            return EXCLUDED_INTERFACE_PREFIXES.none { lower.startsWith(it) }
        }

        fun isEligibleInterface(networkInterface: NetworkInterface): Boolean =
            isEligibleInterface(
                NetworkInterfaceDetails(
                    name = networkInterface.name,
                    isLoopback = networkInterface.isLoopback,
                    isUp = networkInterface.isUp,
                    isVirtual = networkInterface.isVirtual,
                )
            )

        fun discoverBroadcastAddresses(): List<InetAddress> {
            val broadcasts = mutableListOf<InetAddress>()
            val interfaces = runCatching { NetworkInterface.getNetworkInterfaces() }.getOrNull() ?: return broadcasts
            for (networkInterface in interfaces.asSequence()) {
                runCatching {
                    if (!isEligibleInterface(networkInterface)) return@runCatching
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
