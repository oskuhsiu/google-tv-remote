package dev.local.androidtvremote

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import dev.local.androidtvremote.ui.RemoteApp
import dev.local.androidtvremote.ui.theme.AndroidTvRemoteTheme

class MainActivity : ComponentActivity() {
    private val viewModel: RemoteViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AndroidTvRemoteTheme {
                RemoteApp(viewModel)
            }
        }
    }

    override fun onStop() {
        viewModel.onBackground()
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        viewModel.onForeground()
    }
}
