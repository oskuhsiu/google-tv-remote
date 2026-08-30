package dev.local.androidtvremote

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.core.net.toUri
import dev.local.androidtvremote.floating.FloatingRemoteService
import dev.local.androidtvremote.ui.RemoteApp
import dev.local.androidtvremote.ui.theme.AndroidTvRemoteTheme

class MainActivity : ComponentActivity() {
    private val viewModel: RemoteViewModel by viewModels()
    private var overlayPermissionGranted = false
    private var overlayPermissionRequestInFlight = false
    private val overlayPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        overlayPermissionRequestInFlight = false
        overlayPermissionGranted = Settings.canDrawOverlays(this)
        viewModel.setFloatingEnabled(overlayPermissionGranted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overlayPermissionGranted = Settings.canDrawOverlays(this)
        enableEdgeToEdge()
        setContent {
            AndroidTvRemoteTheme {
                RemoteApp(
                    viewModel = viewModel,
                    onFloatingEnabledChange = ::setFloatingEnabled,
                )
            }
        }
    }

    override fun onStop() {
        if (isFinishing || overlayPermissionRequestInFlight) {
            viewModel.onBackground()
        } else {
            val enteredFloatingMode = viewModel.shouldEnterFloatingMode(
                Settings.canDrawOverlays(this),
            ) && FloatingRemoteService.show(this)
            if (!enteredFloatingMode) viewModel.onBackground()
        }
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        overlayPermissionGranted = Settings.canDrawOverlays(this)
        if (!overlayPermissionGranted && viewModel.floatingEnabled.value) {
            viewModel.setFloatingEnabled(false)
        }
        FloatingRemoteService.hide(this)
        viewModel.onForeground()
    }

    private fun setFloatingEnabled(enabled: Boolean) {
        if (!enabled) {
            viewModel.setFloatingEnabled(false)
            return
        }
        overlayPermissionGranted = Settings.canDrawOverlays(this)
        if (overlayPermissionGranted) {
            viewModel.setFloatingEnabled(true)
            return
        }
        overlayPermissionRequestInFlight = true
        overlayPermissionLauncher.launch(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                "package:$packageName".toUri(),
            ),
        )
    }
}
