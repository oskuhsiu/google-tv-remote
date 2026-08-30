package dev.local.androidtvremote.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import dev.local.androidtvremote.R
import dev.local.androidtvremote.TvCandidate

@Composable
fun PairingScreen(
    padding: PaddingValues,
    candidate: TvCandidate,
    pairingCode: String,
    submitting: Boolean,
    onPairingCodeChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(padding).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = 420.dp).fillMaxWidth()) {
            Spacer(Modifier.height(36.dp))
            Text(stringResource(R.string.pair_tv), style = MaterialTheme.typography.headlineLarge)
            Spacer(Modifier.height(10.dp))
            Text(candidate.name, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.pairing_instructions),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(28.dp))
            OutlinedTextField(
                value = pairingCode,
                onValueChange = onPairingCodeChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.pairing_code)) },
                supportingText = { Text(stringResource(R.string.six_hex_characters)) },
                singleLine = true,
                enabled = !submitting,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = onSubmit,
                enabled = pairingCode.length == 6 && !submitting,
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) {
                if (submitting) CircularProgressIndicator(strokeWidth = 2.dp)
                else Text(stringResource(R.string.pair))
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.cancel))
            }
        }
    }
}
