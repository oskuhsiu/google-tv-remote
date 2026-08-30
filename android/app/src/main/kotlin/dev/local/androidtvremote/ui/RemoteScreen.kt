package dev.local.androidtvremote.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.VolumeDown
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.PowerSettingsNew
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import dev.local.androidtvremote.R
import dev.local.androidtvremote.RemoteCommand
import dev.local.androidtvremote.RemoteKeyAction
import dev.local.androidtvremote.TvDevice
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Suppress("DEPRECATION") // D-pad left/right are physical directions and must not mirror in RTL.
@Composable
fun RemoteScreen(
    padding: PaddingValues,
    device: TvDevice,
    enabled: Boolean,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
    onDisconnect: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(padding)
            .padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(device.name, style = MaterialTheme.typography.headlineSmall)
                    Text(
                        if (enabled) stringResource(R.string.connected) else stringResource(R.string.reconnecting),
                        color = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RemoteIconKey(
                        command = RemoteCommand.POWER,
                        label = stringResource(R.string.power),
                        icon = Icons.Rounded.PowerSettingsNew,
                        enabled = enabled,
                        modifier = Modifier.size(48.dp).testTag("remote_key_power"),
                        shape = CircleShape,
                        onCommand = onCommand,
                    )
                    TextButton(
                        onClick = onDisconnect,
                        modifier = Modifier.heightIn(min = 48.dp).testTag("remote_disconnect"),
                        contentPadding = PaddingValues(horizontal = 12.dp),
                    ) { Text(stringResource(R.string.disconnect)) }
                }
            }

            Spacer(Modifier.height(20.dp))
            Text(
                stringResource(R.string.remote_controls),
                style = MaterialTheme.typography.titleMedium,
            )
            Spacer(Modifier.height(16.dp))

            RemoteIconKey(
                command = RemoteCommand.UP,
                label = stringResource(R.string.up),
                icon = Icons.Rounded.KeyboardArrowUp,
                enabled = enabled,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .size(68.dp)
                    .testTag("remote_key_up"),
                shape = CircleShape,
                onCommand = onCommand,
            )
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.align(Alignment.CenterHorizontally),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RemoteIconKey(
                    command = RemoteCommand.LEFT,
                    label = stringResource(R.string.left),
                    icon = Icons.Rounded.KeyboardArrowLeft,
                    enabled = enabled,
                    modifier = Modifier.size(68.dp).testTag("remote_key_left"),
                    shape = CircleShape,
                    onCommand = onCommand,
                )
                RemoteOkKey(
                    label = stringResource(R.string.select),
                    text = stringResource(R.string.ok),
                    enabled = enabled,
                    modifier = Modifier.size(68.dp).testTag("remote_key_select"),
                    onCommand = onCommand,
                )
                RemoteIconKey(
                    command = RemoteCommand.RIGHT,
                    label = stringResource(R.string.right),
                    icon = Icons.Rounded.KeyboardArrowRight,
                    enabled = enabled,
                    modifier = Modifier.size(68.dp).testTag("remote_key_right"),
                    shape = CircleShape,
                    onCommand = onCommand,
                )
            }
            Spacer(Modifier.height(8.dp))
            RemoteIconKey(
                command = RemoteCommand.DOWN,
                label = stringResource(R.string.down),
                icon = Icons.Rounded.KeyboardArrowDown,
                enabled = enabled,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .size(68.dp)
                    .testTag("remote_key_down"),
                shape = CircleShape,
                onCommand = onCommand,
            )

            Spacer(Modifier.height(24.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                RemoteIconKey(
                    command = RemoteCommand.BACK,
                    label = stringResource(R.string.back),
                    icon = Icons.AutoMirrored.Rounded.ArrowBack,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(56.dp).testTag("remote_key_back"),
                    onCommand = onCommand,
                )
                RemoteIconKey(
                    command = RemoteCommand.HOME,
                    label = stringResource(R.string.home),
                    icon = Icons.Rounded.Home,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(56.dp).testTag("remote_key_home"),
                    onCommand = onCommand,
                )
                RemoteIconKey(
                    command = RemoteCommand.MENU,
                    label = stringResource(R.string.menu),
                    icon = Icons.Rounded.Menu,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(56.dp).testTag("remote_key_menu"),
                    onCommand = onCommand,
                )
            }
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                RemoteIconKey(
                    command = RemoteCommand.VOLUME_DOWN,
                    label = stringResource(R.string.volume_down),
                    icon = Icons.AutoMirrored.Rounded.VolumeDown,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(56.dp).testTag("remote_key_volume_down"),
                    onCommand = onCommand,
                )
                RemoteIconKey(
                    command = RemoteCommand.MUTE,
                    label = stringResource(R.string.mute),
                    icon = Icons.AutoMirrored.Rounded.VolumeOff,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(56.dp).testTag("remote_key_mute"),
                    onCommand = onCommand,
                )
                RemoteIconKey(
                    command = RemoteCommand.VOLUME_UP,
                    label = stringResource(R.string.volume_up),
                    icon = Icons.AutoMirrored.Rounded.VolumeUp,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(56.dp).testTag("remote_key_volume_up"),
                    onCommand = onCommand,
                )
            }
        }
    }
}

@Composable
private fun RemoteIconKey(
    command: RemoteCommand,
    label: String,
    icon: ImageVector,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(18.dp),
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
) {
    RemoteKeySurface(
        command = command,
        label = label,
        enabled = enabled,
        modifier = modifier,
        shape = shape,
        onCommand = onCommand,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(28.dp),
        )
    }
}

@Composable
private fun RemoteOkKey(
    label: String,
    text: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
) {
    RemoteKeySurface(
        command = RemoteCommand.SELECT,
        label = label,
        enabled = enabled,
        modifier = modifier,
        shape = CircleShape,
        emphasized = true,
        onCommand = onCommand,
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun RemoteKeySurface(
    command: RemoteCommand,
    label: String,
    enabled: Boolean,
    modifier: Modifier,
    shape: Shape,
    emphasized: Boolean = false,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
    content: @Composable () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val currentOnCommand by rememberUpdatedState(onCommand)
    var pressed by remember { mutableStateOf(false) }
    val pressHandler = remember {
        RemotePressHandler { pressedCommand, action ->
            currentOnCommand(pressedCommand, action)
        }
    }
    val initialHaptic = {
        haptics.performHapticFeedback(HapticFeedbackType.VirtualKey)
    }
    val longHaptic = {
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }
    val launchCommand: (suspend () -> Unit) -> Unit = { block ->
        coroutineScope.launch {
            try {
                block()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // The ViewModel has already exposed the command error.
            }
        }
    }
    val keySemantics = Modifier.semantics(mergeDescendants = true) {
        contentDescription = label
        role = Role.Button
        if (!enabled) {
            disabled()
        } else {
            onClick(label = label) {
                initialHaptic()
                launchCommand {
                    currentOnCommand(command, RemoteKeyAction.SHORT)
                }
                true
            }
            if (command == RemoteCommand.SELECT) {
                onLongClick(label = label) {
                    initialHaptic()
                    longHaptic()
                    launchCommand {
                        var longStarted = false
                        try {
                            currentOnCommand(command, RemoteKeyAction.START_LONG)
                            longStarted = true
                        } finally {
                            if (longStarted) {
                                withContext(NonCancellable) {
                                    currentOnCommand(command, RemoteKeyAction.END_LONG)
                                }
                            }
                        }
                    }
                    true
                }
            }
        }
    }
    val pointerInput = Modifier.pointerInput(command, enabled) {
        if (!enabled) return@pointerInput
        coroutineScope {
            val gestureScope = this
            try {
                while (isActive) {
                    val released = CompletableDeferred<Boolean>()
                    lateinit var pressJob: Job
                    awaitPointerEventScope {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        down.consume()
                        pressed = true
                        initialHaptic()
                        pressJob = gestureScope.launch {
                            try {
                                pressHandler.press(
                                    command = command,
                                    awaitRelease = { released.await() },
                                    onLongPress = longHaptic,
                                )
                            } catch (error: CancellationException) {
                                throw error
                            } catch (_: Throwable) {
                                // The ViewModel has already exposed the command error.
                            }
                        }
                        val up = waitForUpOrCancellation()
                        up?.consume()
                        released.complete(up != null)
                    }
                    pressJob.join()
                    pressed = false
                }
            } finally {
                pressed = false
            }
        }
    }
    val containerColor = when {
        emphasized && pressed -> MaterialTheme.colorScheme.primaryContainer
        emphasized -> MaterialTheme.colorScheme.primary
        pressed -> MaterialTheme.colorScheme.secondaryContainer
        else -> MaterialTheme.colorScheme.surfaceVariant
    }
    val contentColor = when {
        emphasized && pressed -> MaterialTheme.colorScheme.onPrimaryContainer
        emphasized -> MaterialTheme.colorScheme.onPrimary
        pressed -> MaterialTheme.colorScheme.onSecondaryContainer
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(
        modifier = modifier
            .then(pointerInput)
            .then(keySemantics)
            .focusable(enabled = enabled)
            .alpha(if (enabled) 1f else 0.45f),
        shape = shape,
        color = containerColor,
        contentColor = contentColor,
        border = if (emphasized) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            content()
        }
    }
}
