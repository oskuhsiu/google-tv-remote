package dev.local.androidtvremote

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class RemoteViewModel(application: Application) : AndroidViewModel(application) {
    private val controller: RemoteController = AndroidRemoteController(application, viewModelScope)

    val remoteState: StateFlow<RemoteState> = controller.state
    val discoveredCandidates: StateFlow<List<TvCandidate>> = controller.discoveredCandidates

    private val mutableManualHost = MutableStateFlow("")
    val manualHost: StateFlow<String> = mutableManualHost.asStateFlow()

    private val mutablePairingCode = MutableStateFlow("")
    val pairingCode: StateFlow<String> = mutablePairingCode.asStateFlow()

    private val mutableTransientError = MutableStateFlow<RemoteError?>(null)
    val transientError: StateFlow<RemoteError?> = mutableTransientError.asStateFlow()

    private val lifecycleMutex = Mutex()
    private val initialization = viewModelScope.async { controller.initialize() }

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
        launchAction {
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

    fun connectRemembered() = launchAction { controller.connectRemembered() }

    fun connect(candidate: TvCandidate) = launchAction { controller.connect(candidate) }

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

    fun disconnect() = launchAction { controller.disconnect() }

    fun forget() = launchAction { controller.forget() }

    fun onBackground() = launchAction {
        lifecycleMutex.withLock {
            initialization.await()
            controller.enterBackground()
        }
    }

    fun onForeground() = launchAction {
        lifecycleMutex.withLock {
            initialization.await()
            controller.enterForeground()
        }
    }

    fun clearTransientError() {
        mutableTransientError.value = null
    }

    private fun launchAction(block: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                block()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                showTransientError(error)
            }
        }
    }

    private fun showTransientError(error: Throwable) {
        mutableTransientError.value = (error as? RemoteOperationException)?.error
            ?: RemoteError.UNKNOWN
    }

    override fun onCleared() {
        controller.close()
        super.onCleared()
    }
}
