package dev.local.androidtvremote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import dev.local.androidtvremote.R

@Composable
internal fun WolMacGuideDialog(onDismiss: () -> Unit) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier.fillMaxSize().testTag("wol_mac_guide"),
            color = MaterialTheme.colorScheme.background,
        ) {
            Column(
                modifier = Modifier.safeDrawingPadding(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Row(
                    modifier = Modifier.widthIn(max = 600.dp).fillMaxWidth().padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier.size(48.dp).testTag("wol_mac_guide_back"),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Rounded.ArrowBack,
                            contentDescription = stringResource(R.string.back),
                        )
                    }
                    Text(
                        text = stringResource(R.string.wol_mac_guide_title),
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.weight(1f).padding(horizontal = 8.dp)
                            .semantics { heading() },
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Column(
                    modifier = Modifier.weight(1f).widthIn(max = 600.dp).fillMaxWidth()
                        .verticalScroll(rememberScrollState()).padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    GuideStep(
                        title = stringResource(R.string.wol_mac_guide_step_one_title),
                        description = stringResource(R.string.wol_mac_guide_step_one_description),
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        GuideStep(
                            title = stringResource(R.string.wol_mac_guide_step_two_title),
                            description = stringResource(R.string.wol_mac_guide_step_two_description),
                        )
                        ModelMenuExample(
                            model = stringResource(R.string.wol_mac_guide_google_model),
                            path = stringResource(R.string.wol_mac_guide_google_path),
                        )
                        ModelMenuExample(
                            model = stringResource(R.string.wol_mac_guide_tcl_model),
                            path = stringResource(R.string.wol_mac_guide_tcl_path),
                        )
                        ModelMenuExample(
                            model = stringResource(R.string.wol_mac_guide_sony_model),
                            path = stringResource(R.string.wol_mac_guide_sony_path),
                        )
                    }
                    GuideStep(
                        title = stringResource(R.string.wol_mac_guide_step_three_title),
                        description = stringResource(R.string.wol_mac_guide_step_three_description),
                    )
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                text = stringResource(R.string.wol_mac_guide_standby_title),
                                style = MaterialTheme.typography.titleMedium,
                                modifier = Modifier.semantics { heading() },
                            )
                            Text(
                                text = stringResource(R.string.wol_mac_guide_standby_description),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                }
                Button(
                    onClick = onDismiss,
                    modifier = Modifier.widthIn(max = 600.dp).fillMaxWidth()
                        .padding(horizontal = 24.dp, vertical = 16.dp).heightIn(min = 48.dp)
                        .testTag("wol_mac_guide_done"),
                ) {
                    Text(stringResource(R.string.wol_mac_guide_return))
                }
            }
        }
    }
}

@Composable
private fun GuideStep(title: String, description: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ModelMenuExample(model: String, path: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(text = model, style = MaterialTheme.typography.labelLarge)
        Text(
            text = path,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
