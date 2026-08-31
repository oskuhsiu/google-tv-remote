package dev.local.androidtvremote.floating

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.automirrored.rounded.VolumeDown
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.local.androidtvremote.R
import dev.local.androidtvremote.RemoteCommand
import dev.local.androidtvremote.RemoteKeyAction
import dev.local.androidtvremote.ui.RemotePressHandler
import kotlin.math.hypot
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

@Composable
internal fun FloatingRemoteOverlay(
    expanded: Boolean,
    deviceName: String,
    onExpand: () -> Unit,
    onCollapse: () -> Unit,
    onDrag: (Float, Float) -> Unit,
    onDragEnd: () -> Unit,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
    onExit: () -> Unit,
    onOpenFullRemote: () -> Unit,
    maximumHeightDp: Int,
) {
    if (expanded) {
        ExpandedRemote(
            deviceName = deviceName,
            onCollapse = onCollapse,
            onDrag = onDrag,
            onDragEnd = onDragEnd,
            onCommand = onCommand,
            onExit = onExit,
            onOpenFullRemote = onOpenFullRemote,
            maximumHeightDp = maximumHeightDp,
        )
    } else {
        FloatingBubble(
            onExpand = onExpand,
            onDrag = onDrag,
            onDragEnd = onDragEnd,
            onOpenFullRemote = onOpenFullRemote,
        )
    }
}

@Composable
private fun FloatingBubble(
    onExpand: () -> Unit,
    onDrag: (Float, Float) -> Unit,
    onDragEnd: () -> Unit,
    onOpenFullRemote: () -> Unit,
) {
    val expandLabel = stringResource(R.string.expand_floating_remote)
    val openFullRemoteLabel = stringResource(R.string.open_full_remote)
    val haptics = LocalHapticFeedback.current
    Surface(
        modifier = Modifier
            .padding(4.dp)
            .size(60.dp)
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    var totalX = 0f
                    var totalY = 0f
                    var dragging = false
                    val resolvedBeforeLongPress = withTimeoutOrNull(
                        viewConfiguration.longPressTimeoutMillis,
                    ) {
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                            if (change == null || !change.pressed) {
                                onExpand()
                                return@withTimeoutOrNull true
                            }
                            val delta = change.positionChange()
                            totalX += delta.x
                            totalY += delta.y
                            if (hypot(totalX, totalY) >= viewConfiguration.touchSlop) {
                                dragging = true
                                change.consume()
                                onDrag(totalX, totalY)
                                return@withTimeoutOrNull true
                            }
                        }
                        true
                    }
                    if (resolvedBeforeLongPress == null) {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onOpenFullRemote()
                        waitForUpOrCancellation()
                    } else if (dragging) {
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                            if (change == null || !change.pressed) {
                                onDragEnd()
                                break
                            }
                            val delta = change.positionChange()
                            if (delta.x != 0f || delta.y != 0f) {
                                change.consume()
                                onDrag(delta.x, delta.y)
                            }
                        }
                    }
                }
            }
            .semantics {
                contentDescription = expandLabel
                role = Role.Button
                onClick(expandLabel) {
                    onExpand()
                    true
                }
                onLongClick(openFullRemoteLabel) {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onOpenFullRemote()
                    true
                }
            }
            .testTag("floating_remote_bubble"),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.primary,
        contentColor = MaterialTheme.colorScheme.onPrimary,
        shadowElevation = 10.dp,
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(
                imageVector = Icons.Rounded.Tv,
                contentDescription = null,
                modifier = Modifier.size(28.dp),
            )
        }
    }
}

@Composable
private fun ExpandedRemote(
    deviceName: String,
    onCollapse: () -> Unit,
    onDrag: (Float, Float) -> Unit,
    onDragEnd: () -> Unit,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
    onExit: () -> Unit,
    onOpenFullRemote: () -> Unit,
    maximumHeightDp: Int,
) {
    val maximumHeight = maximumHeightDp.coerceAtLeast(240).dp
    Surface(
        modifier = Modifier.padding(6.dp).fillMaxWidth().testTag("floating_remote_panel"),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shadowElevation = 12.dp,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column(
            Modifier
                .heightIn(max = maximumHeight)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(58.dp)
                    .pointerInput(Unit) {
                        detectDragGestures(
                            onDragEnd = onDragEnd,
                            onDragCancel = onDragEnd,
                        ) { change, amount ->
                            change.consume()
                            onDrag(amount.x, amount.y)
                        }
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .height(58.dp)
                        .clickable(onClick = onOpenFullRemote)
                        .testTag("floating_connected_tv"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(contentAlignment = Alignment.TopEnd) {
                        Surface(
                            modifier = Modifier.size(42.dp),
                            shape = RoundedCornerShape(13.dp),
                            color = MaterialTheme.colorScheme.surfaceVariant,
                        ) {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Icon(Icons.Rounded.Tv, contentDescription = null, modifier = Modifier.size(23.dp))
                            }
                        }
                        Surface(modifier = Modifier.size(10.dp), shape = CircleShape, color = ConnectedGreen) {}
                    }
                    Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                        Text(
                            stringResource(R.string.connected),
                            color = ConnectedGreen,
                            style = MaterialTheme.typography.labelMedium,
                        )
                        Text(
                            deviceName,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleSmall,
                        )
                    }
                }
                IconButton(
                    onClick = onCollapse,
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(Icons.Rounded.ExpandMore, contentDescription = stringResource(R.string.collapse))
                }
            }

            Spacer(Modifier.height(8.dp))
            DPad(onCommand)
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FloatingKey(
                    command = RemoteCommand.BACK,
                    icon = Icons.AutoMirrored.Rounded.ArrowBack,
                    label = stringResource(R.string.back),
                    modifier = Modifier.weight(1f).height(52.dp),
                    onCommand = onCommand,
                )
                FloatingKey(
                    command = RemoteCommand.HOME,
                    icon = Icons.Rounded.Home,
                    label = stringResource(R.string.home),
                    modifier = Modifier.weight(1f).height(52.dp),
                    onCommand = onCommand,
                )
            }
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FloatingKey(
                    command = RemoteCommand.VOLUME_DOWN,
                    icon = Icons.AutoMirrored.Rounded.VolumeDown,
                    label = stringResource(R.string.volume_down),
                    modifier = Modifier.weight(1f).height(48.dp),
                    iconSize = 24.dp,
                    onCommand = onCommand,
                )
                FloatingKey(
                    command = RemoteCommand.MUTE,
                    icon = Icons.AutoMirrored.Rounded.VolumeOff,
                    label = stringResource(R.string.mute),
                    modifier = Modifier.weight(1f).height(48.dp),
                    iconSize = 24.dp,
                    onCommand = onCommand,
                )
                FloatingKey(
                    command = RemoteCommand.VOLUME_UP,
                    icon = Icons.AutoMirrored.Rounded.VolumeUp,
                    label = stringResource(R.string.volume_up),
                    modifier = Modifier.weight(1f).height(48.dp),
                    iconSize = 24.dp,
                    onCommand = onCommand,
                )
            }

            Spacer(Modifier.height(14.dp))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = onExit,
                modifier = Modifier.fillMaxWidth().height(50.dp).testTag("floating_remote_exit"),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                ),
            ) {
                Icon(Icons.AutoMirrored.Rounded.Logout, contentDescription = null, modifier = Modifier.size(21.dp))
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.exit_floating_remote))
            }
            Text(
                stringResource(R.string.exit_floating_remote_description),
                modifier = Modifier.fillMaxWidth().padding(top = 5.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelSmall,
            )
        }
    }
}

@Composable
@Suppress("DEPRECATION") // D-pad left/right are physical directions and must not mirror in RTL.
private fun DPad(onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        FloatingKey(
            command = RemoteCommand.UP,
            icon = Icons.Rounded.KeyboardArrowUp,
            label = stringResource(R.string.up),
            modifier = Modifier.size(58.dp),
            shape = RoundedCornerShape(19.dp),
            onCommand = onCommand,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            FloatingKey(
                command = RemoteCommand.LEFT,
                icon = Icons.Rounded.KeyboardArrowLeft,
                label = stringResource(R.string.left),
                modifier = Modifier.size(58.dp),
                shape = RoundedCornerShape(19.dp),
                onCommand = onCommand,
            )
            FloatingKey(
                command = RemoteCommand.SELECT,
                label = stringResource(R.string.select),
                modifier = Modifier.size(58.dp),
                shape = CircleShape,
                emphasized = true,
                onCommand = onCommand,
            ) {
                Text(stringResource(R.string.ok), style = MaterialTheme.typography.titleSmall)
            }
            FloatingKey(
                command = RemoteCommand.RIGHT,
                icon = Icons.Rounded.KeyboardArrowRight,
                label = stringResource(R.string.right),
                modifier = Modifier.size(58.dp),
                shape = RoundedCornerShape(19.dp),
                onCommand = onCommand,
            )
        }
        FloatingKey(
            command = RemoteCommand.DOWN,
            icon = Icons.Rounded.KeyboardArrowDown,
            label = stringResource(R.string.down),
            modifier = Modifier.size(58.dp),
            shape = RoundedCornerShape(19.dp),
            onCommand = onCommand,
        )
    }
}

@Composable
private fun FloatingKey(
    command: RemoteCommand,
    label: String,
    modifier: Modifier,
    onCommand: suspend (RemoteCommand, RemoteKeyAction) -> Unit,
    icon: ImageVector? = null,
    iconSize: Dp = 27.dp,
    shape: Shape = RoundedCornerShape(16.dp),
    emphasized: Boolean = false,
    content: (@Composable () -> Unit)? = null,
) {
    val haptics = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val currentOnCommand by rememberUpdatedState(onCommand)
    var pressed by remember { mutableStateOf(false) }
    val handler = remember {
        RemotePressHandler { pressedCommand, action ->
            currentOnCommand(pressedCommand, action)
        }
    }
    val sendForAccessibility = {
        haptics.performHapticFeedback(HapticFeedbackType.VirtualKey)
        coroutineScope.launch { runCatching { currentOnCommand(command, RemoteKeyAction.SHORT) } }
    }
    val pointerInput = Modifier.pointerInput(command) {
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
                        haptics.performHapticFeedback(HapticFeedbackType.VirtualKey)
                        pressJob = gestureScope.launch {
                            try {
                                handler.press(
                                    command = command,
                                    awaitRelease = { released.await() },
                                    onLongPress = {
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    },
                                )
                            } catch (error: CancellationException) {
                                throw error
                            } catch (_: Throwable) {
                                // A lost session is handled by the service state observer.
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
    val keySemantics = Modifier.semantics(mergeDescendants = true) {
        contentDescription = label
        role = Role.Button
        onClick(label) {
            sendForAccessibility()
            true
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
            .focusable(),
        shape = shape,
        color = containerColor,
        contentColor = contentColor,
        border = if (emphasized) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            when {
                content != null -> content()
                icon != null -> Icon(icon, contentDescription = null, modifier = Modifier.size(iconSize))
            }
        }
    }
}

private val ConnectedGreen = Color(0xFF52D273)
