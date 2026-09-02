package dev.local.androidtvremote.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Clear
import androidx.compose.material.icons.rounded.PowerSettingsNew
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import dev.local.androidtvremote.R
import dev.local.androidtvremote.wol.WolPacket

@Composable
fun WolSettingsDialog(
    initialMac: String?,
    onDismiss: () -> Unit,
    onSave: (String?) -> Unit,
    onSendPacket: (String, onSent: () -> Unit) -> Unit,
) {
    var macInput by rememberSaveable { mutableStateOf(initialMac ?: "") }
    var inputError by rememberSaveable { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = stringResource(R.string.wol_dialog_title),
                style = MaterialTheme.typography.titleLarge,
            )
        },
        text = {
            Column(Modifier.fillMaxWidth()) {
                Text(
                    text = stringResource(R.string.wol_dialog_description),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                OutlinedTextField(
                    value = macInput,
                    onValueChange = { newValue ->
                        val filtered = newValue.uppercase()
                            .filter { it.isDigit() || it in 'A'..'F' || it == ':' || it == '-' }
                            .take(23)
                        macInput = filtered
                        inputError = null
                    },
                    label = { Text(stringResource(R.string.wol_mac_address)) },
                    placeholder = { Text(stringResource(R.string.wol_mac_placeholder)) },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Characters,
                        autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Ascii,
                    ),
                    trailingIcon = {
                        if (macInput.isNotEmpty()) {
                            IconButton(onClick = {
                                macInput = ""
                                inputError = null
                            }) {
                                Icon(Icons.Rounded.Clear, contentDescription = null)
                            }
                        }
                    },
                    singleLine = true,
                    isError = inputError != null,
                    supportingText = inputError?.let { { Text(it) } },
                    modifier = Modifier.fillMaxWidth().testTag("wol_mac_input"),
                )
                if (WolPacket.isValidMac(macInput)) {
                    Spacer(Modifier.height(8.dp))
                    TextButton(
                        onClick = {
                            val formatted = WolPacket.formatMac(macInput)
                            onSendPacket(formatted) {
                                Toast.makeText(context, R.string.wol_packet_sent, Toast.LENGTH_SHORT).show()
                            }
                        },
                        modifier = Modifier.align(Alignment.End).testTag("wol_send_packet_btn"),
                    ) {
                        Icon(
                            Icons.Rounded.PowerSettingsNew,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.wol_send_packet))
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val trimmed = macInput.trim()
                    if (trimmed.isEmpty()) {
                        onSave(null)
                        onDismiss()
                    } else if (WolPacket.isValidMac(trimmed)) {
                        onSave(WolPacket.formatMac(trimmed))
                        onDismiss()
                    } else {
                        inputError = context.getString(R.string.wol_invalid_mac)
                    }
                },
                modifier = Modifier.testTag("wol_save_btn"),
            ) {
                Text(stringResource(R.string.wol_save))
            }
        },
        dismissButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!initialMac.isNullOrBlank()) {
                    TextButton(
                        onClick = {
                            onSave(null)
                            onDismiss()
                        },
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                        modifier = Modifier.testTag("wol_clear_btn"),
                    ) {
                        Text(stringResource(R.string.wol_clear))
                    }
                }
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.cancel))
                }
            }
        },
    )
}
