package dev.local.androidtvremote.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import dev.local.androidtvremote.TvCandidate
import dev.local.androidtvremote.TvSource
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

internal class RememberedTvResolver(context: Context) {
    private val nsdManager = context.getSystemService(NsdManager::class.java)
    private val wifiManager = context.applicationContext.getSystemService(WifiManager::class.java)

    @Suppress("DEPRECATION")
    suspend fun resolve(locatorKey: String): TvCandidate? {
        val service = RememberedTvService.parse(locatorKey) ?: return null
        return withContext(Dispatchers.Main.immediate) {
            val finished = AtomicBoolean(false)
            var listener: NsdManager.ResolveListener? = null
            var multicastLock: WifiManager.MulticastLock? = null
            try {
                withTimeoutOrNull(RESOLVE_TIMEOUT_MILLIS) {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        multicastLock = wifiManager.createMulticastLock(MULTICAST_LOCK_TAG)
                        multicastLock?.apply {
                            setReferenceCounted(false)
                            acquire()
                        }
                    }
                    suspendCancellableCoroutine<TvCandidate?> { continuation ->
                        val resolveListener = object : NsdManager.ResolveListener {
                            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                                if (!continuation.isActive || !finished.compareAndSet(false, true)) return
                                val candidate = try {
                                    serviceInfo.host?.hostAddress?.let { host ->
                                        TvCandidate(service.locatorKey, service.name, host, TvSource.DISCOVERY)
                                    }
                                } catch (_: RuntimeException) {
                                    null
                                }
                                continuation.resume(candidate)
                            }

                            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                                if (!continuation.isActive || !finished.compareAndSet(false, true)) return
                                continuation.resume(null)
                            }
                        }
                        listener = resolveListener
                        val serviceInfo = NsdServiceInfo().apply {
                            serviceName = service.name
                            serviceType = TvDiscovery.SERVICE_TYPE
                        }
                        nsdManager.resolveService(serviceInfo, resolveListener)
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: RuntimeException) {
                null
            } finally {
                // On older Android versions the request cannot be stopped, but its late
                // callbacks see an inactive continuation or the finished flag and do nothing.
                val pending = !finished.getAndSet(true)
                if (pending && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    listener?.let { runCatching { nsdManager.stopServiceResolution(it) } }
                }
                multicastLock?.let { lock ->
                    runCatching { if (lock.isHeld) lock.release() }
                }
            }
        }
    }

    private companion object {
        const val RESOLVE_TIMEOUT_MILLIS = 5_000L
        const val MULTICAST_LOCK_TAG = "android-tv-remote-remembered-resolution"
    }
}
