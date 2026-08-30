package dev.local.androidtvremote.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import dev.local.androidtvremote.TvCandidate
import dev.local.androidtvremote.TvSource
import java.util.ArrayDeque
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class TvDiscovery(context: Context) {
    private val nsdManager = context.getSystemService(NsdManager::class.java)
    private val wifiManager = context.applicationContext.getSystemService(WifiManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mutableDevices = MutableStateFlow<List<TvCandidate>>(emptyList())

    val devices: StateFlow<List<TvCandidate>> = mutableDevices.asStateFlow()

    private val pendingResolve = ArrayDeque<NsdServiceInfo>()
    private val queuedKeys = mutableSetOf<String>()
    private val resolved = linkedMapOf<String, TvCandidate>()
    private var resolving = false
    private var active = false
    private var requested = false
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    fun start() {
        mainHandler.post {
            requested = true
            if (active) return@post
            beginDiscovery()
        }
    }

    fun stop() {
        mainHandler.post {
            requested = false
            val listener = discoveryListener
            if (listener != null && active) {
                try {
                    nsdManager.stopServiceDiscovery(listener)
                } catch (_: RuntimeException) {
                    finishStop(clearDevices = true)
                }
            } else {
                finishStop(clearDevices = true)
            }
        }
    }

    private fun beginDiscovery() {
        active = true
        val listener = createDiscoveryListener()
        discoveryListener = listener
        try {
            acquireMulticastLock()
            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (_: RuntimeException) {
            requested = false
            finishStop(clearDevices = true)
        }
    }

    private fun createDiscoveryListener(): NsdManager.DiscoveryListener =
        object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                mainHandler.post {
                    if (!requested || !active || normalizeType(serviceInfo.serviceType) != SERVICE_TYPE) return@post
                    val key = serviceKey(serviceInfo)
                    if (key !in queuedKeys && key !in resolved) {
                        queuedKeys += key
                        pendingResolve += serviceInfo
                        resolveNext()
                    }
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                mainHandler.post {
                    val key = serviceKey(serviceInfo)
                    queuedKeys -= key
                    pendingResolve.removeAll { serviceKey(it) == key }
                    if (resolved.remove(key) != null) publish()
                }
            }

            override fun onDiscoveryStopped(serviceType: String) {
                mainHandler.post {
                    finishStop(clearDevices = true)
                    if (requested) beginDiscovery()
                }
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                mainHandler.post {
                    requested = false
                    finishStop(clearDevices = true)
                }
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                mainHandler.post {
                    finishStop(clearDevices = true)
                    if (requested) beginDiscovery()
                }
            }
        }

    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (!active || resolving) return
        val service = pendingResolve.pollFirst() ?: return
        resolving = true
        nsdManager.resolveService(
            service,
            object : NsdManager.ResolveListener {
                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    mainHandler.post {
                        resolving = false
                        val key = serviceKey(serviceInfo)
                        queuedKeys -= key
                        if (active && requested) {
                            serviceInfo.host?.hostAddress?.let { host ->
                                resolved[key] = TvCandidate(
                                    locatorKey = key,
                                    name = serviceInfo.serviceName,
                                    host = host,
                                    source = TvSource.DISCOVERY,
                                )
                                publish()
                            }
                        }
                        resolveNext()
                    }
                }

                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    mainHandler.post {
                        resolving = false
                        queuedKeys -= serviceKey(serviceInfo)
                        resolveNext()
                    }
                }
            },
        )
    }

    private fun publish() {
        mutableDevices.value = resolved.values.sortedBy { it.name.lowercase() }
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        multicastLock = wifiManager.createMulticastLock(MULTICAST_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun finishStop(clearDevices: Boolean) {
        active = false
        discoveryListener = null
        resolving = false
        pendingResolve.clear()
        queuedKeys.clear()
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        if (clearDevices) {
            resolved.clear()
            publish()
        }
    }

    private fun serviceKey(info: NsdServiceInfo): String =
        "local.|${normalizeType(info.serviceType)}|${info.serviceName}"

    private fun normalizeType(value: String): String = value.trimEnd('.')

    companion object {
        const val SERVICE_TYPE = "_androidtvremote2._tcp"
        private const val MULTICAST_LOCK_TAG = "android-tv-remote-discovery"
    }
}
