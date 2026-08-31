package dev.local.androidtvremote

import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.core.net.toUri
import androidx.core.content.ContextCompat
import dev.local.androidtvremote.floating.FloatingRemoteService
import dev.local.androidtvremote.ui.RemoteApp
import dev.local.androidtvremote.ui.theme.AndroidTvRemoteTheme

class MainActivity : ComponentActivity() {
    private val viewModel: RemoteViewModel by viewModels()
    private var overlayPermissionGranted = false
    private var overlayPermissionRequestInFlight = false
    private val microphonePermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            Toast.makeText(this, R.string.voice_permission_ready, Toast.LENGTH_SHORT).show()
        } else {
            viewModel.voicePermissionDenied()
        }
    }
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
                    onVoiceStart = ::startVoice,
                    onVoiceStop = viewModel::stopVoice,
                )
            }
        }
    }

    override fun onStop() {
        viewModel.stopVoice()
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

    private fun startVoice() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            viewModel.startVoice()
        } else {
            microphonePermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
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
