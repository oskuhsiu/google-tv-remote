package dev.local.androidtvremote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import dev.local.androidtvremote.R
import dev.local.androidtvremote.RemoteError
import dev.local.androidtvremote.TvDevice
import dev.local.androidtvremote.TvCandidate

@Composable
fun DeviceScreen(
    padding: PaddingValues,
    rememberedDevice: TvDevice?,
    discoveredCandidates: List<TvCandidate>,
    manualHost: String,
    failure: RemoteError?,
    onManualHostChange: (String) -> Unit,
    onManualConnect: () -> Unit,
    onRememberedConnect: () -> Unit,
    onCandidateConnect: (TvCandidate) -> Unit,
    onForget: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(padding)
            .padding(horizontal = 24.dp, vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth()) {
            Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineLarge)
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.device_intro),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyLarge,
            )

            failure?.let {
                Spacer(Modifier.height(20.dp))
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Text(
                        stringResource(it.messageResource()),
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
            }

            if (rememberedDevice == null) {
                Spacer(Modifier.height(28.dp))
                Text(stringResource(R.string.nearby_tvs), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(10.dp))
                if (discoveredCandidates.isEmpty()) {
                    Card {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(modifier = Modifier.height(24.dp), strokeWidth = 2.dp)
                            Column {
                                Text(stringResource(R.string.looking_for_tvs))
                                Text(
                                    stringResource(R.string.discovery_hint),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        discoveredCandidates.forEach { candidate ->
                            OutlinedButton(
                                onClick = { onCandidateConnect(candidate) },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(64.dp)
                                    .testTag("discovered_tv_${candidate.locatorKey}"),
                            ) {
                                Column(Modifier.fillMaxWidth()) {
                                    Text(candidate.name, style = MaterialTheme.typography.titleMedium)
                                    Text(
                                        candidate.host,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            rememberedDevice?.let { device ->
                Spacer(Modifier.height(28.dp))
                Text(stringResource(R.string.last_tv), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(10.dp))
                Card {
                    Column(Modifier.padding(16.dp)) {
                        Text(device.name, style = MaterialTheme.typography.titleLarge)
                        Text(
                            stringResource(R.string.ready_to_reconnect),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(16.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(
                                onClick = onRememberedConnect,
                                modifier = Modifier.weight(1f).testTag("remembered_tv_connect"),
                            ) {
                                Text(stringResource(R.string.connect))
                            }
                            OutlinedButton(onClick = onForget) {
                                Text(stringResource(R.string.forget))
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(28.dp))
            Text(stringResource(R.string.manual_ip), style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(
                value = manualHost,
                onValueChange = onManualHostChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.tv_ip_address)) },
                placeholder = { Text("192.168.1.25") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = onManualConnect,
                enabled = manualHost.isNotBlank(),
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) {
                Text(stringResource(R.string.connect))
            }
            Spacer(Modifier.height(12.dp))
            Text(
                stringResource(R.string.manual_ip_hint),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
