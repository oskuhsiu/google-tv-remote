package dev.local.androidtvremote.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.local.androidtvremote.R
import dev.local.androidtvremote.RemoteState
import dev.local.androidtvremote.RemoteViewModel

@Composable
fun RemoteApp(viewModel: RemoteViewModel) {
    val remoteState by viewModel.remoteState.collectAsStateWithLifecycle()
    val discoveredCandidates by viewModel.discoveredCandidates.collectAsStateWithLifecycle()
    val manualHost by viewModel.manualHost.collectAsStateWithLifecycle()
    val pairingCode by viewModel.pairingCode.collectAsStateWithLifecycle()
    val transientError by viewModel.transientError.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val transientMessage = transientError?.let { stringResource(it.messageResource()) }

    LaunchedEffect(transientMessage) {
        transientMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearTransientError()
        }
    }

    Surface(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
        Scaffold(snackbarHost = { SnackbarHost(snackbarHostState) }) { padding ->
            Box(Modifier.fillMaxSize()) {
                when (val state = remoteState) {
                    is RemoteState.Connecting -> LoadingScreen(
                        padding = padding,
                        title = stringResource(R.string.connecting_to, state.candidate.name),
                    )

                    is RemoteState.NeedsPairing -> PairingScreen(
                        padding = padding,
                        candidate = state.candidate,
                        pairingCode = pairingCode,
                        submitting = false,
                        onPairingCodeChange = viewModel::updatePairingCode,
                        onSubmit = viewModel::submitPairingCode,
                        onCancel = viewModel::disconnect,
                    )

                    is RemoteState.Pairing -> PairingScreen(
                        padding = padding,
                        candidate = state.candidate,
                        pairingCode = pairingCode,
                        submitting = true,
                        onPairingCodeChange = viewModel::updatePairingCode,
                        onSubmit = viewModel::submitPairingCode,
                        onCancel = viewModel::disconnect,
                    )

                    is RemoteState.Connected -> RemoteScreen(
                        padding = padding,
                        device = state.device,
                        enabled = true,
                        onCommand = viewModel::send,
                        onDisconnect = viewModel::disconnect,
                    )

                    is RemoteState.Reconnecting -> RemoteScreen(
                        padding = padding,
                        device = state.device,
                        enabled = false,
                        onCommand = viewModel::send,
                        onDisconnect = viewModel::disconnect,
                    )

                    is RemoteState.Discovering -> DeviceScreen(
                        padding = padding,
                        rememberedDevice = null,
                        discoveredCandidates = discoveredCandidates,
                        manualHost = manualHost,
                        failure = null,
                        onManualHostChange = viewModel::updateManualHost,
                        onManualConnect = viewModel::connectManual,
                        onRememberedConnect = viewModel::connectRemembered,
                        onCandidateConnect = viewModel::connect,
                        onForget = viewModel::forget,
                    )

                    is RemoteState.Disconnected -> DeviceScreen(
                        padding = padding,
                        rememberedDevice = state.device,
                        discoveredCandidates = discoveredCandidates,
                        manualHost = manualHost,
                        failure = null,
                        onManualHostChange = viewModel::updateManualHost,
                        onManualConnect = viewModel::connectManual,
                        onRememberedConnect = viewModel::connectRemembered,
                        onCandidateConnect = viewModel::connect,
                        onForget = viewModel::forget,
                    )

                    is RemoteState.Failed -> DeviceScreen(
                        padding = padding,
                        rememberedDevice = state.device,
                        discoveredCandidates = discoveredCandidates,
                        manualHost = manualHost,
                        failure = state.reason,
                        onManualHostChange = viewModel::updateManualHost,
                        onManualConnect = viewModel::connectManual,
                        onRememberedConnect = viewModel::connectRemembered,
                        onCandidateConnect = viewModel::connect,
                        onForget = viewModel::forget,
                    )

                    RemoteState.Idle -> DeviceScreen(
                        padding = padding,
                        rememberedDevice = null,
                        discoveredCandidates = discoveredCandidates,
                        manualHost = manualHost,
                        failure = null,
                        onManualHostChange = viewModel::updateManualHost,
                        onManualConnect = viewModel::connectManual,
                        onRememberedConnect = viewModel::connectRemembered,
                        onCandidateConnect = viewModel::connect,
                        onForget = viewModel::forget,
                    )
                }
            }
        }
    }
}
