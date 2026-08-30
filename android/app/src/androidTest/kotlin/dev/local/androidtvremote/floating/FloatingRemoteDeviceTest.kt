package dev.local.androidtvremote.floating

import android.content.Intent
import android.graphics.Rect
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.Settings
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.local.androidtvremote.AndroidRemoteController
import dev.local.androidtvremote.MainActivity
import dev.local.androidtvremote.RemoteApplication
import dev.local.androidtvremote.RemoteState
import dev.local.androidtvremote.TvCandidate
import dev.local.androidtvremote.TvDevice
import dev.local.androidtvremote.TvSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FloatingRemoteDeviceTest {
    @Test
    fun connectedAppBackgroundsIntoBubbleWhichExpandsAndExits() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = ApplicationProvider.getApplicationContext<RemoteApplication>()
        val device = UiDevice.getInstance(instrumentation)
        val runtime = app.remoteRuntime
        runBlocking { runtime.awaitInitialized() }
        val originalOverlayMode = overlayPermissionMode(instrumentation, app.packageName)

        try {
            app.stopService(Intent(app, FloatingRemoteService::class.java))
            waitForServiceStopped(device)
            grantOverlayPermission(instrumentation, app.packageName)
            runtime.floatingPreferences.setEnabled(true)
            forceForeground(runtime.controller as AndroidRemoteController)
            forceConnectedState(runtime.controller)
            ActivityScenario.launch(MainActivity::class.java).use {
                assertTrue(
                    "Floating option did not appear in the connected app",
                    device.wait(
                        Until.hasObject(By.text(app.getString(dev.local.androidtvremote.R.string.floating_remote))),
                        5_000,
                    ),
                )
                capture(instrumentation, "google-tv-remote-connected-screen.png")
                device.executeShellCommand("am start -W -a android.settings.SETTINGS")

                val bubble = checkNotNull(waitForOverlay(device, expanded = false)) {
                    "Floating bubble did not appear after backgrounding"
                }
                capture(instrumentation, "google-tv-remote-floating-bubble.png")
                val bubbleControl = device.findObject(
                    By.desc(app.getString(dev.local.androidtvremote.R.string.expand_floating_remote)),
                )
                assumeTrue(
                    "This platform does not expose overlay content to injected test input",
                    bubbleControl != null,
                )

                bubbleControl.click()
                val initialExpanded = checkNotNull(waitForOverlay(device, expanded = true)) {
                    "Tapping the bubble did not open compact controls"
                }
                val collapse = device.wait(
                    Until.findObject(By.desc(app.getString(dev.local.androidtvremote.R.string.collapse))),
                    3_000,
                )
                checkNotNull(collapse) { "Compact controls did not expose a collapse action" }.click()
                val restoredBubble = checkNotNull(waitForOverlay(device, expanded = false)) {
                    "Collapsing compact controls did not restore the bubble"
                }

                val originalCenterX = restoredBubble.centerX()
                val originalCenterY = restoredBubble.centerY()
                device.swipe(
                    originalCenterX,
                    originalCenterY,
                    originalCenterX,
                    (originalCenterY + 120).coerceAtMost(device.displayHeight - 80),
                    20,
                )
                SystemClock.sleep(500)
                val movedBubble = checkNotNull(
                    waitForOverlay(device, expanded = false, timeoutMillis = 2_000),
                ) { "Floating bubble disappeared while dragging" }
                capture(instrumentation, "google-tv-remote-floating-dragged.png")
                assertTrue(
                    "Floating bubble did not move",
                    movedBubble.centerY() > originalCenterY + 60,
                )

                val movedControl = device.wait(
                    Until.findObject(
                        By.desc(app.getString(dev.local.androidtvremote.R.string.expand_floating_remote)),
                    ),
                    3_000,
                )
                checkNotNull(movedControl) { "Moved bubble lost its tap action" }.click()
                val expanded = checkNotNull(waitForOverlay(device, expanded = true)) {
                    "Expanded remote did not appear"
                }
                capture(instrumentation, "google-tv-remote-floating-expanded.png")

                val exit = device.findObject(
                    By.text(app.getString(dev.local.androidtvremote.R.string.exit_floating_remote)),
                )
                if (exit != null) {
                    exit.click()
                } else {
                    device.click(expanded.centerX(), expanded.top + expanded.height() * 7 / 8)
                }
                assertTrue(
                    "Floating remote did not close",
                    waitForOverlay(device, present = false) == null,
                )
                assertFalse(runtime.floatingPreferences.enabled.value)
            }
        } finally {
            runtime.floatingPreferences.setEnabled(false)
            app.stopService(Intent(app, FloatingRemoteService::class.java))
            waitForServiceStopped(device)
            runBlocking { runtime.controller.enterBackground() }
            setOverlayPermission(instrumentation, app.packageName, originalOverlayMode)
        }
    }

    @Test
    fun longPressingBubbleOpensTheFullRemote() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = ApplicationProvider.getApplicationContext<RemoteApplication>()
        val device = UiDevice.getInstance(instrumentation)
        val runtime = app.remoteRuntime
        runBlocking { runtime.awaitInitialized() }
        val originalOverlayMode = overlayPermissionMode(instrumentation, app.packageName)

        try {
            app.stopService(Intent(app, FloatingRemoteService::class.java))
            waitForServiceStopped(device)
            grantOverlayPermission(instrumentation, app.packageName)
            runtime.floatingPreferences.setEnabled(true)
            forceForeground(runtime.controller as AndroidRemoteController)
            forceConnectedState(runtime.controller)
            ActivityScenario.launch(MainActivity::class.java).use {
                assertTrue(
                    device.wait(
                        Until.hasObject(By.text(app.getString(dev.local.androidtvremote.R.string.floating_remote))),
                        5_000,
                    ),
                )
                device.executeShellCommand("am start -W -a android.settings.SETTINGS")
                val bubble = checkNotNull(waitForOverlay(device, expanded = false)) {
                    "Floating bubble did not appear"
                }
                val bubbleControl = device.findObject(
                    By.desc(app.getString(dev.local.androidtvremote.R.string.expand_floating_remote)),
                )
                assumeTrue(
                    "This platform does not expose overlay content to injected test input",
                    bubbleControl != null,
                )

                bubbleControl.longClick()
                assertTrue(
                    "Long press did not open the full remote",
                    device.wait(
                        Until.hasObject(By.text(app.getString(dev.local.androidtvremote.R.string.remote_controls))),
                        5_000,
                    ),
                )
                assertTrue(
                    device.wait(
                        Until.gone(
                            By.desc(app.getString(dev.local.androidtvremote.R.string.expand_floating_remote)),
                        ),
                        5_000,
                    ),
                )
                waitForServiceStopped(device)
                runtime.floatingPreferences.setEnabled(false)
            }
        } finally {
            runtime.floatingPreferences.setEnabled(false)
            app.stopService(Intent(app, FloatingRemoteService::class.java))
            waitForServiceStopped(device)
            runBlocking { runtime.controller.enterBackground() }
            setOverlayPermission(instrumentation, app.packageName, originalOverlayMode)
        }
    }

    @Test
    fun returningToTheAppHidesTheFloatingBubble() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = ApplicationProvider.getApplicationContext<RemoteApplication>()
        val device = UiDevice.getInstance(instrumentation)
        val runtime = app.remoteRuntime
        runBlocking { runtime.awaitInitialized() }
        val originalOverlayMode = overlayPermissionMode(instrumentation, app.packageName)

        try {
            app.stopService(Intent(app, FloatingRemoteService::class.java))
            waitForServiceStopped(device)
            grantOverlayPermission(instrumentation, app.packageName)
            runtime.floatingPreferences.setEnabled(true)
            forceForeground(runtime.controller as AndroidRemoteController)
            forceConnectedState(runtime.controller)
            ActivityScenario.launch(MainActivity::class.java).use {
                assertTrue(
                    device.wait(
                        Until.hasObject(By.text(app.getString(dev.local.androidtvremote.R.string.floating_remote))),
                        5_000,
                    ),
                )
                device.executeShellCommand("am start -W -a android.settings.SETTINGS")
                assertTrue(waitForOverlay(device, expanded = false) != null)

                device.executeShellCommand(
                    "am start -W -n ${app.packageName}/dev.local.androidtvremote.MainActivity",
                )
                assertTrue(
                    "Floating bubble remained above the foreground app",
                    waitForOverlay(device, present = false) == null,
                )
                runtime.floatingPreferences.setEnabled(false)
            }
        } finally {
            runtime.floatingPreferences.setEnabled(false)
            app.stopService(Intent(app, FloatingRemoteService::class.java))
            waitForServiceStopped(device)
            runBlocking { runtime.controller.enterBackground() }
            setOverlayPermission(instrumentation, app.packageName, originalOverlayMode)
        }
    }

    @Test
    fun startupConnectionCanBeCancelledFromTheLoadingScreen() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = ApplicationProvider.getApplicationContext<RemoteApplication>()
        val device = UiDevice.getInstance(instrumentation)
        val runtime = app.remoteRuntime
        runBlocking { runtime.awaitInitialized() }
        forceForeground(runtime.controller as AndroidRemoteController)
        forceState(
            runtime.controller,
            RemoteState.Connecting(
                TvCandidate(
                    locatorKey = "startup-test",
                    name = "Startup TV",
                    host = "192.0.2.1",
                    source = TvSource.MANUAL,
                ),
            ),
        )

        ActivityScenario.launch(MainActivity::class.java).use {
            val cancel = device.wait(
                Until.findObject(By.text(app.getString(dev.local.androidtvremote.R.string.cancel_connection))),
                5_000,
            )
            assertTrue("Startup connection cancel action did not appear", cancel != null)
            capture(instrumentation, "google-tv-remote-startup-cancel.png")
            cancel.click()
            assertTrue(
                "Cancel did not return to the device screen",
                device.wait(
                    Until.hasObject(By.text(app.getString(dev.local.androidtvremote.R.string.manual_ip))),
                    5_000,
                ),
            )
            assertFalse(runtime.controller.state.value is RemoteState.Connecting)
            assertFalse(runtime.controller.state.value is RemoteState.Pairing)
        }
    }

    private fun grantOverlayPermission(
        instrumentation: android.app.Instrumentation,
        packageName: String,
    ) {
        setOverlayPermission(instrumentation, packageName, "allow")
        repeat(40) {
            if (Settings.canDrawOverlays(instrumentation.targetContext)) return
            SystemClock.sleep(50)
        }
        assertTrue("Overlay permission was not granted", false)
    }

    private fun overlayPermissionMode(
        instrumentation: android.app.Instrumentation,
        packageName: String,
    ): String {
        val output = executeShell(
            instrumentation,
            "appops get $packageName SYSTEM_ALERT_WINDOW",
        )
        return Regex("SYSTEM_ALERT_WINDOW: (\\w+)")
            .find(output)
            ?.groupValues
            ?.get(1)
            ?: "default"
    }

    private fun setOverlayPermission(
        instrumentation: android.app.Instrumentation,
        packageName: String,
        mode: String,
    ) {
        executeShell(instrumentation, "appops set $packageName SYSTEM_ALERT_WINDOW $mode")
    }

    private fun forceConnectedState(controller: AndroidRemoteController) {
        forceState(
            controller,
            RemoteState.Connected(
                TvDevice(
                    id = "device-test",
                    name = "Living Room TV",
                    source = TvSource.MANUAL,
                ),
            ),
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun forceState(controller: AndroidRemoteController, value: RemoteState) {
        val field = AndroidRemoteController::class.java.getDeclaredField("mutableState")
        field.isAccessible = true
        val state = field.get(controller) as MutableStateFlow<RemoteState>
        state.value = value
    }

    private fun forceForeground(controller: AndroidRemoteController) {
        val field = AndroidRemoteController::class.java.getDeclaredField("isForeground")
        field.isAccessible = true
        field.setBoolean(controller, true)
    }

    private fun waitForOverlay(
        device: UiDevice,
        present: Boolean = true,
        expanded: Boolean? = null,
        timeoutMillis: Long = 5_000,
    ): Rect? {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        var lastBounds: Rect?
        do {
            lastBounds = overlayBounds(device)
            if (!present && lastBounds == null) return null
            if (present && lastBounds != null) {
                val matchesSize = when (expanded) {
                    true -> kotlin.math.abs(lastBounds.width() - lastBounds.height()) >
                        minOf(lastBounds.width(), lastBounds.height()) / 3
                    false -> kotlin.math.abs(lastBounds.width() - lastBounds.height()) < 12
                    null -> true
                }
                if (matchesSize) return lastBounds
            }
            SystemClock.sleep(100)
        } while (SystemClock.uptimeMillis() < deadline)
        return if (present) null else lastBounds
    }

    private fun waitForServiceStopped(device: UiDevice, timeoutMillis: Long = 5_000) {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        do {
            val services = device.executeShellCommand(
                "dumpsys activity services io.github.oskuhsiu.googletvremote",
            )
            if ("FloatingRemoteService" !in services) return
            SystemClock.sleep(100)
        } while (SystemClock.uptimeMillis() < deadline)
        error("FloatingRemoteService did not stop before the next device-test fixture")
    }

    private fun overlayBounds(device: UiDevice): Rect? {
        val windows = device.executeShellCommand("dumpsys window windows")
        val packagePattern = Regex.escape("io.github.oskuhsiu.googletvremote")
        val block = Regex(
            "Window #\\d+ Window\\{[^\\n]*$packagePattern[^\\n]*\\}:.*?" +
                "(?=\\n\\s*Window #\\d+|\\z)",
            RegexOption.DOT_MATCHES_ALL,
        ).findAll(windows)
            .map(MatchResult::value)
            .firstOrNull { "APPLICATION_OVERLAY" in it }
            ?: return null

        Regex(
            "(?:mFrame|frame)=\\[(-?\\d+),(-?\\d+)]\\[(-?\\d+),(-?\\d+)]",
        ).find(block)?.groupValues?.let { values ->
            return Rect(
                values[1].toInt(),
                values[2].toInt(),
                values[3].toInt(),
                values[4].toInt(),
            )
        }

        return Regex(
            "mAttrs=\\{\\((-?\\d+),(-?\\d+)\\)\\((\\d+)x(\\d+)\\)[^\\n]*" +
                "ty=APPLICATION_OVERLAY",
        ).find(block)?.groupValues?.let { values ->
            val left = values[1].toInt()
            val top = values[2].toInt()
            Rect(
                left,
                top,
                left + values[3].toInt(),
                top + values[4].toInt(),
            )
        }
    }

    private fun capture(
        instrumentation: android.app.Instrumentation,
        name: String,
    ) {
        executeShell(instrumentation, "screencap -p /sdcard/Download/$name")
    }

    private fun executeShell(
        instrumentation: android.app.Instrumentation,
        command: String,
    ): String = instrumentation.uiAutomation.executeShellCommand(command)
        .let(ParcelFileDescriptor::AutoCloseInputStream)
        .bufferedReader()
        .use { it.readText() }
}
