package dev.local.androidtvremote.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val RemoteColors = darkColorScheme(
    primary = Color(0xFFFF6A2A),
    onPrimary = Color.White,
    background = Color(0xFF101114),
    onBackground = Color(0xFFF2F2F3),
    surface = Color(0xFF1A1C20),
    onSurface = Color(0xFFF2F2F3),
    surfaceVariant = Color(0xFF272A2F),
    onSurfaceVariant = Color(0xFFC7C8CC),
    error = Color(0xFFFFB4AB),
)

@Composable
fun AndroidTvRemoteTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = RemoteColors,
        content = content,
    )
}

