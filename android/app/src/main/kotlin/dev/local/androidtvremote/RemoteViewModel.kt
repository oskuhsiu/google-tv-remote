package dev.local.androidtvremote

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class RemoteViewModel(application: Application) : AndroidViewModel(application) {
    private val runtime = (application as RemoteApplication).remoteRuntime
    private val controller: RemoteController = runtime.controller

    val remoteState: StateFlow<RemoteState> = controller.state
    val discoveredCandidates: StateFlow<List<TvCandidate>> = controller.discoveredCandidates
    val floatingEnabled: StateFlow<Boolean> = runtime.floatingPreferences.enabled

    private val mutableManualHost = MutableStateFlow("")
    val manualHost: StateFlow<String> = mutableManualHost.asStateFlow()

    private val mutablePairingCode = MutableStateFlow("")
    val pairingCode: StateFlow<String> = mutablePairingCode.asStateFlow()

    private val mutableTransientError = MutableStateFlow<RemoteError?>(null)
    val transientError: StateFlow<RemoteError?> = mutableTransientError.asStateFlow()

    private val lifecycleMutex = Mutex()
    private var connectionJob: Job? = null

    fun updateManualHost(value: String) {
        mutableManualHost.value = value.trimStart().take(255)
    }

    fun updatePairingCode(value: String) {
        mutablePairingCode.value = value
            .uppercase()
            .filter { it.isDigit() || it in 'A'..'F' }
            .take(6)
    }

    fun connectManual() {
        val host = manualHost.value.trim()
        if (host.isEmpty() || host.any(Char::isWhitespace)) {
            mutableTransientError.value = RemoteError.TV_NOT_FOUND
            return
        }
        launchConnection {
            controller.connect(
                TvCandidate(
                    locatorKey = "manual:$host",
                    name = host,
                    host = host,
                    source = TvSource.MANUAL,
                ),
            )
        }
    }

    fun connectRemembered() = launchConnection { controller.connectRemembered() }

    fun connect(candidate: TvCandidate) = launchConnection { controller.connect(candidate) }

    fun submitPairingCode() {
        val code = pairingCode.value
        launchAction {
            controller.submitPairingCode(code)
            mutablePairingCode.value = ""
        }
    }

    suspend fun send(command: RemoteCommand, action: RemoteKeyAction) {
        try {
            controller.send(command, action)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            showTransientError(error)
            throw error
        }
    }

    fun cancelConnection() = disconnect()

    fun disconnect() {
        connectionJob?.cancel()
        launchAction { controller.disconnect() }
    }

    fun forget() = launchAction { controller.forget() }

    fun onBackground() {
        connectionJob?.cancel()
        launchAction {
            lifecycleMutex.withLock {
                runtime.awaitInitialized()
                controller.enterBackground()
            }
        }
    }

    fun onForeground() {
        if (connectionJob?.isActive == true) return
        launchConnection {
            lifecycleMutex.withLock {
                runtime.awaitInitialized()
                controller.enterForeground()
            }
        }
    }

    fun setFloatingEnabled(enabled: Boolean) {
        runtime.floatingPreferences.setEnabled(enabled)
    }

    fun shouldEnterFloatingMode(hasOverlayPermission: Boolean): Boolean =
        floatingEnabled.value &&
            hasOverlayPermission &&
            remoteState.value is RemoteState.Connected

    fun clearTransientError() {
        mutableTransientError.value = null
    }

    private fun launchAction(block: suspend () -> Unit) {
        viewModelScope.launch {
            runAction(block)
        }
    }

    private fun launchConnection(block: suspend () -> Unit) {
        connectionJob?.cancel()
        connectionJob = viewModelScope.launch {
            runAction(block)
        }
    }

    private suspend fun runAction(block: suspend () -> Unit) {
        try {
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            showTransientError(error)
        }
    }

    private fun showTransientError(error: Throwable) {
        mutableTransientError.value = (error as? RemoteOperationException)?.error
            ?: RemoteError.UNKNOWN
    }

    override fun onCleared() {
        connectionJob?.cancel()
        super.onCleared()
    }
}
