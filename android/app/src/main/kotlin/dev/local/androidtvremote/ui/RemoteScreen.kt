package dev.local.androidtvremote.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PowerSettingsNew
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import dev.local.androidtvremote.VoiceState
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
    floatingEnabled: Boolean,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
    onDisconnect: () -> Unit,
    onFloatingEnabledChange: (Boolean) -> Unit,
    voiceState: VoiceState,
    onVoiceStart: () -> Unit,
    onVoiceStop: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var deviceMenuExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(padding)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.weight(1f)) {
                    TextButton(
                        onClick = { deviceMenuExpanded = true },
                        contentPadding = PaddingValues(horizontal = 0.dp, vertical = 4.dp),
                    ) {
                        Column(horizontalAlignment = Alignment.Start) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(device.name, style = MaterialTheme.typography.headlineSmall)
                                Icon(
                                    Icons.Rounded.KeyboardArrowDown,
                                    contentDescription = null,
                                    modifier = Modifier.size(22.dp),
                                )
                            }
                            Text(
                                if (enabled) stringResource(R.string.connected) else stringResource(R.string.reconnecting),
                                color = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                    DropdownMenu(
                        expanded = deviceMenuExpanded,
                        onDismissRequest = { deviceMenuExpanded = false },
                    ) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.menu)) },
                            leadingIcon = { Icon(Icons.Rounded.Menu, contentDescription = null) },
                            enabled = enabled,
                            onClick = {
                                deviceMenuExpanded = false
                                scope.launch {
                                    try {
                                        onCommand(RemoteCommand.MENU, RemoteKeyAction.SHORT)
                                    } catch (_: Throwable) {
                                    }
                                }
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.disconnect), color = MaterialTheme.colorScheme.error) },
                            onClick = {
                                deviceMenuExpanded = false
                                onDisconnect()
                            },
                        )
                    }
                }

                RemoteIconKey(
                    command = RemoteCommand.POWER,
                    label = stringResource(R.string.power),
                    icon = Icons.Rounded.PowerSettingsNew,
                    enabled = enabled,
                    modifier = Modifier.size(52.dp).testTag("remote_key_power"),
                    shape = CircleShape,
                    onCommand = onCommand,
                )
            }

            Spacer(Modifier.height(18.dp))
            VoiceButton(
                voiceState = voiceState,
                enabled = enabled && voiceState != VoiceState.UNAVAILABLE,
                onStart = onVoiceStart,
                onStop = onVoiceStop,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            )
            Spacer(Modifier.height(18.dp))

            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val dPadSize = maxWidth.coerceAtMost(320.dp)
                val keySize = if (dPadSize < 280.dp) 58.dp else 66.dp
                Surface(
                    modifier = Modifier.align(Alignment.Center).size(dPadSize),
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.45f)),
                ) {
                    Box(Modifier.fillMaxSize()) {
                        RemoteIconKey(
                            command = RemoteCommand.UP,
                            label = stringResource(R.string.up),
                            icon = Icons.Rounded.KeyboardArrowUp,
                            enabled = enabled,
                            modifier = Modifier.align(Alignment.TopCenter).padding(top = 14.dp).size(keySize).testTag("remote_key_up"),
                            shape = CircleShape,
                            transparent = true,
                            onCommand = onCommand,
                        )
                        RemoteIconKey(
                            command = RemoteCommand.DOWN,
                            label = stringResource(R.string.down),
                            icon = Icons.Rounded.KeyboardArrowDown,
                            enabled = enabled,
                            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp).size(keySize).testTag("remote_key_down"),
                            shape = CircleShape,
                            transparent = true,
                            onCommand = onCommand,
                        )
                        RemoteIconKey(
                            command = RemoteCommand.LEFT,
                            label = stringResource(R.string.left),
                            icon = Icons.Rounded.KeyboardArrowLeft,
                            enabled = enabled,
                            modifier = Modifier.align(Alignment.CenterStart).padding(start = 14.dp).size(keySize).testTag("remote_key_left"),
                            shape = CircleShape,
                            transparent = true,
                            onCommand = onCommand,
                        )
                        RemoteIconKey(
                            command = RemoteCommand.RIGHT,
                            label = stringResource(R.string.right),
                            icon = Icons.Rounded.KeyboardArrowRight,
                            enabled = enabled,
                            modifier = Modifier.align(Alignment.CenterEnd).padding(end = 14.dp).size(keySize).testTag("remote_key_right"),
                            shape = CircleShape,
                            transparent = true,
                            onCommand = onCommand,
                        )
                        RemoteOkKey(
                            label = stringResource(R.string.select),
                            text = stringResource(R.string.ok),
                            enabled = enabled,
                            modifier = Modifier.align(Alignment.Center).size(if (dPadSize < 280.dp) 72.dp else 82.dp).testTag("remote_key_select"),
                            onCommand = onCommand,
                        )
                    }
                }
            }

            Spacer(Modifier.height(20.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                RemoteIconKey(
                    command = RemoteCommand.BACK,
                    label = stringResource(R.string.back),
                    icon = Icons.AutoMirrored.Rounded.ArrowBack,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(58.dp).testTag("remote_key_back"),
                    shape = RoundedCornerShape(22.dp),
                    onCommand = onCommand,
                )
                RemoteIconKey(
                    command = RemoteCommand.HOME,
                    label = stringResource(R.string.home),
                    icon = Icons.Rounded.Home,
                    enabled = enabled,
                    modifier = Modifier.weight(1f).height(58.dp).testTag("remote_key_home"),
                    shape = RoundedCornerShape(22.dp),
                    onCommand = onCommand,
                )
                ActionIconKey(
                    label = stringResource(R.string.floating_remote),
                    icon = Icons.Rounded.PictureInPictureAlt,
                    enabled = enabled,
                    selected = floatingEnabled,
                    modifier = Modifier.weight(1f).height(58.dp).testTag("floating_remote_toggle"),
                    onClick = { onFloatingEnabledChange(!floatingEnabled) },
                )
            }

            Spacer(Modifier.height(12.dp))
            Surface(
                modifier = Modifier.fillMaxWidth().height(58.dp),
                shape = RoundedCornerShape(24.dp),
                color = MaterialTheme.colorScheme.surfaceVariant,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)),
            ) {
                Row(Modifier.fillMaxSize()) {
                    RemoteIconKey(
                        command = RemoteCommand.VOLUME_DOWN,
                        label = stringResource(R.string.volume_down),
                        icon = Icons.AutoMirrored.Rounded.VolumeDown,
                        enabled = enabled,
                        modifier = Modifier.weight(1f).fillMaxSize().testTag("remote_key_volume_down"),
                        shape = RoundedCornerShape(topStart = 24.dp, bottomStart = 24.dp),
                        transparent = true,
                        onCommand = onCommand,
                    )
                    RemoteIconKey(
                        command = RemoteCommand.MUTE,
                        label = stringResource(R.string.mute),
                        icon = Icons.AutoMirrored.Rounded.VolumeOff,
                        enabled = enabled,
                        modifier = Modifier.weight(1f).fillMaxSize().testTag("remote_key_mute"),
                        shape = RoundedCornerShape(0.dp),
                        transparent = true,
                        onCommand = onCommand,
                    )
                    RemoteIconKey(
                        command = RemoteCommand.VOLUME_UP,
                        label = stringResource(R.string.volume_up),
                        icon = Icons.AutoMirrored.Rounded.VolumeUp,
                        enabled = enabled,
                        modifier = Modifier.weight(1f).fillMaxSize().testTag("remote_key_volume_up"),
                        shape = RoundedCornerShape(topEnd = 24.dp, bottomEnd = 24.dp),
                        transparent = true,
                        onCommand = onCommand,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun VoiceButton(
    voiceState: VoiceState,
    enabled: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    val currentOnStart by rememberUpdatedState(onStart)
    val currentOnStop by rememberUpdatedState(onStop)
    val label = stringResource(R.string.hold_to_talk)
    val status = when (voiceState) {
        VoiceState.UNAVAILABLE -> stringResource(R.string.voice_not_supported)
        VoiceState.IDLE -> stringResource(R.string.hold_to_talk)
        VoiceState.STARTING -> stringResource(R.string.voice_starting)
        VoiceState.LISTENING -> stringResource(R.string.voice_listening)
    }

    DisposableEffect(Unit) {
        onDispose { currentOnStop() }
    }

    Surface(
        color = if (voiceState == VoiceState.LISTENING) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
        contentColor = if (voiceState == VoiceState.LISTENING) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.primary,
        shape = CircleShape,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = if (voiceState == VoiceState.LISTENING) 0.9f else 0.55f)),
        modifier = modifier
            .size(76.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .semantics(mergeDescendants = true) {
                contentDescription = "$label, $status"
                role = Role.Button
                if (!enabled) {
                    disabled()
                } else {
                    onClick(label = label) {
                        if (voiceState == VoiceState.IDLE) currentOnStart() else currentOnStop()
                        true
                    }
                }
            }
            .focusable(enabled)
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    currentOnStart()
                    try {
                        waitForUpOrCancellation()
                    } finally {
                        currentOnStop()
                    }
                }
            }
            .testTag("remote_voice_hold"),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Mic, contentDescription = null, modifier = Modifier.size(34.dp))
        }
    }
}

@Composable
private fun ActionIconKey(
    label: String,
    icon: ImageVector,
    enabled: Boolean,
    selected: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Surface(
        modifier = modifier
            .alpha(if (enabled) 1f else 0.45f)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = label },
        shape = RoundedCornerShape(22.dp),
        color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
        contentColor = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(28.dp))
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
    transparent: Boolean = false,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
) {
    RemoteKeySurface(
        command = command,
        label = label,
        enabled = enabled,
        modifier = modifier,
        shape = shape,
        transparent = transparent,
        onCommand = onCommand,
    ) {
        Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(28.dp))
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
    transparent: Boolean = false,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
    content: @Composable () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val currentOnCommand by rememberUpdatedState(onCommand)
    var pressed by remember { mutableStateOf(false) }
    val pressHandler = remember {
        RemotePressHandler { pressedCommand, action -> currentOnCommand(pressedCommand, action) }
    }
    val initialHaptic = { haptics.performHapticFeedback(HapticFeedbackType.VirtualKey) }
    val longHaptic = { haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    val launchCommand: (suspend () -> Unit) -> Unit = { block ->
        coroutineScope.launch {
            try {
                block()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
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
                launchCommand { currentOnCommand(command, RemoteKeyAction.SHORT) }
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
                                withContext(NonCancellable) { currentOnCommand(command, RemoteKeyAction.END_LONG) }
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
                                pressHandler.press(command = command, awaitRelease = { released.await() }, onLongPress = longHaptic)
                            } catch (error: CancellationException) {
                                throw error
                            } catch (_: Throwable) {
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
        transparent && pressed -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.75f)
        transparent -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0f)
        emphasized && pressed -> MaterialTheme.colorScheme.primaryContainer
        emphasized -> MaterialTheme.colorScheme.surface
        pressed -> MaterialTheme.colorScheme.primaryContainer
        else -> MaterialTheme.colorScheme.surfaceVariant
    }
    val contentColor = when {
        emphasized -> MaterialTheme.colorScheme.onSurface
        pressed -> MaterialTheme.colorScheme.onPrimaryContainer
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
        border = if (transparent) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { content() }
    }
}
