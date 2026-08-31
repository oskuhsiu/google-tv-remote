package dev.local.androidtvremote.floating

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import dev.local.androidtvremote.MainActivity
import dev.local.androidtvremote.R
import dev.local.androidtvremote.RemoteApplication
import dev.local.androidtvremote.RemoteState
import dev.local.androidtvremote.ui.theme.AndroidTvRemoteTheme
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield

class FloatingRemoteService : LifecycleService(), SavedStateRegistryOwner, ViewModelStoreOwner {
    private val runtime by lazy { (application as RemoteApplication).remoteRuntime }
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val windowManager by lazy { getSystemService(WindowManager::class.java) }

    private var overlayView: ComposeView? = null
    private var stateJob: Job? = null
    private var expanded by mutableStateOf(false)
    private var deviceName by mutableStateOf("")
    private var handoffToForeground = false
    private var backgroundHandled = false
    private var stopping = false
    private lateinit var windowLayout: WindowManager.LayoutParams
    private val savedStateController = SavedStateRegistryController.create(this)

    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateController.savedStateRegistry

    override val viewModelStore = ViewModelStore()

    override fun onCreate() {
        savedStateController.performAttach()
        savedStateController.performRestore(null)
        super.onCreate()
        serviceActiveOrRequested = true
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        promoteToForeground()
        when (intent?.action ?: ACTION_SHOW) {
            ACTION_HIDE -> {
                handoffToForeground = true
                removeOverlay()
                stopSelf(startId)
            }

            ACTION_EXIT -> exitFloatingRemote(disablePreference = true)
            ACTION_SHOW -> if (floatingRequested) {
                showFloatingRemote()
            } else {
                handoffToForeground = true
                removeOverlay()
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    private fun showFloatingRemote() {
        handoffToForeground = false
        backgroundHandled = false
        stopping = false
        val connected = runtime.controller.state.value as? RemoteState.Connected
        if (!Settings.canDrawOverlays(this) || connected == null) {
            exitFloatingRemote(disablePreference = false)
            return
        }
        deviceName = connected.device.name
        if (overlayView == null && !addOverlay()) {
            exitFloatingRemote(disablePreference = false)
            return
        }
        if (stateJob == null) {
            stateJob = serviceScope.launch {
                runtime.controller.state.collectLatest { state ->
                    when (state) {
                        is RemoteState.Connected -> deviceName = state.device.name
                        else -> if (!handoffToForeground && overlayView != null) {
                            exitFloatingRemote(disablePreference = false)
                        }
                    }
                }
            }
        }
    }

    private fun promoteToForeground() {
        val name = (runtime.controller.state.value as? RemoteState.Connected)?.device?.name
            ?: getString(R.string.app_name)
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(name),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            } else {
                0
            },
        )
    }

    private fun addOverlay(): Boolean {
        expanded = false
        windowLayout = WindowManager.LayoutParams(
            bubbleWindowSizePx(),
            bubbleWindowSizePx(),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val bounds = currentBounds()
            x = bounds.width() - bubbleWindowSizePx() - edgeMarginPx()
            y = (bounds.height() * 0.28f).roundToInt()
        }
        return attachOverlayView()
    }

    private fun attachOverlayView(): Boolean {
        val view = createOverlayView()
        return try {
            windowManager.addView(view, windowLayout)
            overlayView = view
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun createOverlayView() = ComposeView(this).apply {
        setViewTreeLifecycleOwner(this@FloatingRemoteService)
        setViewTreeSavedStateRegistryOwner(this@FloatingRemoteService)
        setViewTreeViewModelStoreOwner(this@FloatingRemoteService)
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
        setContent {
            AndroidTvRemoteTheme {
                FloatingRemoteOverlay(
                    expanded = expanded,
                    deviceName = deviceName,
                    onExpand = { updateExpanded(true) },
                    onCollapse = { updateExpanded(false) },
                    onDrag = ::moveOverlay,
                    onDragEnd = ::finishMove,
                    onCommand = { command, action ->
                        try {
                            runtime.controller.send(command, action)
                        } catch (error: CancellationException) {
                            throw error
                        } catch (error: Throwable) {
                            exitFloatingRemote(disablePreference = false)
                            throw error
                        }
                    },
                    onExit = { exitFloatingRemote(disablePreference = true) },
                    onOpenFullRemote = ::openFullRemote,
                    maximumHeightDp = maximumOverlayHeightDp(),
                )
            }
        }
    }

    private fun updateExpanded(value: Boolean) {
        if (expanded == value) return
        serviceScope.launch {
            // Finish the current pointer dispatch before replacing the overlay window.
            yield()
            val oldView = overlayView ?: return@launch
            val bounds = currentBounds()
            val wasOnRight = windowLayout.x + windowLayout.width / 2 > bounds.width() / 2
            overlayView = null
            runCatching { windowManager.removeViewImmediate(oldView) }
            expanded = value
            windowLayout.width = if (value) panelWindowWidthPx() else bubbleWindowSizePx()
            windowLayout.height = if (value) WindowManager.LayoutParams.WRAP_CONTENT else bubbleWindowSizePx()
            windowLayout.x = if (wasOnRight) {
                bounds.width() - windowLayout.width - edgeMarginPx()
            } else {
                edgeMarginPx()
            }
            clampPosition()
            if (!attachOverlayView()) exitFloatingRemote(disablePreference = false)
        }
    }

    private fun moveOverlay(deltaX: Float, deltaY: Float) {
        val view = overlayView ?: return
        windowLayout.x += deltaX.roundToInt()
        windowLayout.y += deltaY.roundToInt()
        clampPosition()
        runCatching { windowManager.updateViewLayout(view, windowLayout) }
    }

    private fun finishMove() {
        val view = overlayView ?: return
        val bounds = currentBounds()
        if (!expanded) {
            windowLayout.x = if (windowLayout.x + windowLayout.width / 2 < bounds.width() / 2) {
                edgeMarginPx()
            } else {
                bounds.width() - windowLayout.width - edgeMarginPx()
            }
        }
        clampPosition()
        runCatching { windowManager.updateViewLayout(view, windowLayout) }
        view.sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
    }

    private fun clampPosition() {
        val bounds = currentBounds()
        val measuredHeight = overlayView?.height?.takeIf { it > 0 }
            ?: if (expanded) panelEstimatedHeightPx() else bubbleWindowSizePx()
        windowLayout.x = windowLayout.x.coerceIn(
            edgeMarginPx(),
            (bounds.width() - windowLayout.width - edgeMarginPx()).coerceAtLeast(edgeMarginPx()),
        )
        windowLayout.y = windowLayout.y.coerceIn(
            edgeMarginPx(),
            (bounds.height() - measuredHeight - edgeMarginPx()).coerceAtLeast(edgeMarginPx()),
        )
    }

    private fun exitFloatingRemote(disablePreference: Boolean) {
        if (stopping) return
        stopping = true
        floatingRequested = false
        handoffRequested = false
        if (disablePreference) runtime.floatingPreferences.setEnabled(false)
        backgroundHandled = true
        removeOverlay()
        runtime.scope.launch {
            runtime.awaitInitialized()
            runtime.controller.enterBackground()
            stopSelf()
        }
    }

    private fun openFullRemote() {
        floatingRequested = false
        handoffRequested = true
        handoffToForeground = true
        serviceActiveOrRequested = false
        removeOverlay()
        stopSelf()
        startActivity(fullRemoteIntent())
    }

    private fun removeOverlay() {
        val view = overlayView ?: return
        overlayView = null
        runCatching { windowManager.removeViewImmediate(view) }
    }

    private fun buildNotification(name: String): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            fullRemoteIntent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val exit = PendingIntent.getService(
            this,
            1,
            Intent(this, FloatingRemoteService::class.java).setAction(ACTION_EXIT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.floating_remote))
            .setContentText(getString(R.string.floating_remote_notification, name))
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, getString(R.string.exit_floating_remote), exit)
            .build()
    }

    private fun fullRemoteIntent() = Intent(this, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            getString(R.string.floating_remote_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.floating_remote_channel_description)
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun currentBounds() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        windowManager.currentWindowMetrics.bounds
    } else {
        @Suppress("DEPRECATION")
        android.graphics.Rect(0, 0, resources.displayMetrics.widthPixels, resources.displayMetrics.heightPixels)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()
    private fun edgeMarginPx() = dp(8)
    private fun bubbleWindowSizePx() = dp(68)
    private fun panelWindowWidthPx() = dp(312)
    private fun panelEstimatedHeightPx() = dp(500)
    private fun maximumOverlayHeightDp(): Int =
        (currentBounds().height() / resources.displayMetrics.density).roundToInt() - 16

    override fun onDestroy() {
        if (!floatingRequested) serviceActiveOrRequested = false
        removeOverlay()
        stateJob?.cancel()
        stateJob = null
        serviceScope.cancel()
        viewModelStore.clear()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        if (!handoffToForeground && !handoffRequested && !floatingRequested && !backgroundHandled) {
            runtime.scope.launch {
                runtime.awaitInitialized()
                runtime.controller.enterBackground()
            }
        }
        super.onDestroy()
    }

    companion object {
        private const val ACTION_SHOW = "dev.local.androidtvremote.action.SHOW_FLOATING_REMOTE"
        private const val ACTION_HIDE = "dev.local.androidtvremote.action.HIDE_FLOATING_REMOTE"
        private const val ACTION_EXIT = "dev.local.androidtvremote.action.EXIT_FLOATING_REMOTE"
        private const val NOTIFICATION_CHANNEL_ID = "floating_remote"
        private const val NOTIFICATION_ID = 41

        @Volatile
        private var floatingRequested = false

        @Volatile
        private var handoffRequested = false

        @Volatile
        private var serviceActiveOrRequested = false

        fun show(context: Context): Boolean {
            if (!Settings.canDrawOverlays(context)) return false
            if (floatingRequested) {
                return true
            }
            floatingRequested = true
            handoffRequested = false
            serviceActiveOrRequested = true
            return runCatching {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, FloatingRemoteService::class.java).setAction(ACTION_SHOW),
                )
            }.onFailure {
                floatingRequested = false
                serviceActiveOrRequested = false
            }.isSuccess
        }

        fun hide(context: Context) {
            floatingRequested = false
            handoffRequested = true
            if (!serviceActiveOrRequested) return
            runCatching {
                context.startService(
                    Intent(context, FloatingRemoteService::class.java).setAction(ACTION_HIDE),
                )
            }
        }
    }
}
