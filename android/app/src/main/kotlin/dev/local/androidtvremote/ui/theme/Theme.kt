package dev.local.androidtvremote.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val RemoteColors = darkColorScheme(
    primary = Color(0xFF6EA8FF),
    onPrimary = Color(0xFF071428),
    primaryContainer = Color(0xFF17345F),
    onPrimaryContainer = Color(0xFFD9E7FF),
    secondary = Color(0xFF8FB7F5),
    background = Color(0xFF0B0F16),
    onBackground = Color(0xFFF3F6FB),
    surface = Color(0xFF111722),
    onSurface = Color(0xFFF3F6FB),
    surfaceVariant = Color(0xFF1A2230),
    onSurfaceVariant = Color(0xFFC8D0DC),
    outlineVariant = Color(0xFF354155),
    error = Color(0xFFFF8A80),
)

@Composable
fun AndroidTvRemoteTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = RemoteColors,
        content = content,
    )
}
