package dev.local.androidtvremote

import kotlinx.coroutines.flow.StateFlow

enum class RemoteCommand(val keyCode: Int) {
    UP(19),
    DOWN(20),
    LEFT(21),
    RIGHT(22),
    SELECT(23),
    BACK(4),
    HOME(3),
    MENU(82),
    POWER(26),
    VOLUME_UP(24),
    VOLUME_DOWN(25),
    MUTE(164);

    fun supports(action: RemoteKeyAction): Boolean =
        action == RemoteKeyAction.SHORT || this == SELECT
}

enum class RemoteKeyAction {
    SHORT,
    START_LONG,
    END_LONG,
}

enum class VoiceState {
    UNAVAILABLE,
    IDLE,
    STARTING,
    LISTENING,
}

enum class RemotePressBehavior {
    SINGLE,
    LONG_PRESS,
    REPEAT,
}

object RemotePressPolicy {
    const val LONG_PRESS_MILLIS = 400L
    const val REPEAT_DELAY_MILLIS = 400L
    const val REPEAT_INTERVAL_MILLIS = 100L

    fun behaviorFor(command: RemoteCommand): RemotePressBehavior = when (command) {
        RemoteCommand.SELECT -> RemotePressBehavior.LONG_PRESS
        RemoteCommand.UP,
        RemoteCommand.DOWN,
        RemoteCommand.LEFT,
        RemoteCommand.RIGHT,
        RemoteCommand.VOLUME_UP,
        RemoteCommand.VOLUME_DOWN,
        -> RemotePressBehavior.REPEAT

        else -> RemotePressBehavior.SINGLE
    }
}

enum class TvSource { DISCOVERY, MANUAL }

data class TvCandidate(
    val locatorKey: String,
    val name: String,
    val host: String,
    val source: TvSource,
)

data class TvDevice(
    val id: String,
    val name: String,
    val source: TvSource,
)

data class LastTvRecord(
    val device: TvDevice,
    val lastHost: String,
    val bonjourLocatorKey: String?,
    val lastConnectedAt: Long,
    val clientIdentityFingerprint: String,
    val pairingPeerFingerprint: String,
    val remotePeerFingerprint: String,
)

enum class RemoteError {
    NETWORK_UNREACHABLE,
    TV_NOT_FOUND,
    PAIRING_REQUIRED,
    PAIRING_CODE_INVALID,
    PAIRING_REJECTED,
    PAIRING_TIMEOUT,
    TRUST_CHANGED,
    CONNECTION_LOST,
    VOICE_PERMISSION_DENIED,
    VOICE_SESSION_FAILED,
    TEXT_INPUT_FAILED,
    UNKNOWN,
}

sealed interface RemoteState {
    data object Idle : RemoteState
    data class Discovering(val devices: List<TvCandidate>) : RemoteState
    data class Connecting(val candidate: TvCandidate) : RemoteState
    data class NeedsPairing(val candidate: TvCandidate) : RemoteState
    data class Pairing(val candidate: TvCandidate) : RemoteState
    data class Connected(val device: TvDevice) : RemoteState
    data class Reconnecting(val device: TvDevice, val attempt: Int) : RemoteState
    data class Disconnected(val device: TvDevice?) : RemoteState
    data class Failed(
        val device: TvDevice?,
        val reason: RemoteError,
        val recoverable: Boolean,
    ) : RemoteState
}

object RetryPolicy {
    private val delays = longArrayOf(1_000L, 2_000L, 4_000L)

    fun delayMillis(attempt: Int): Long? = delays.getOrNull(attempt - 1)
}

object TrustTupleValidator {
    fun isComplete(record: LastTvRecord, actualClientFingerprint: String): Boolean =
        record.device.id.isNotBlank() &&
            record.device.name.isNotBlank() &&
            record.lastHost.isNotBlank() &&
            record.clientIdentityFingerprint.isNotBlank() &&
            record.pairingPeerFingerprint.isNotBlank() &&
            record.remotePeerFingerprint.isNotBlank() &&
            record.device.id == record.remotePeerFingerprint &&
            record.clientIdentityFingerprint == actualClientFingerprint
}

enum class ForegroundAction {
    NONE,
    CONNECT_REMEMBERED,
    START_DISCOVERY,
}

object ForegroundPolicy {
    fun action(alreadyForeground: Boolean, hasValidPairing: Boolean): ForegroundAction = when {
        alreadyForeground -> ForegroundAction.NONE
        hasValidPairing -> ForegroundAction.CONNECT_REMEMBERED
        else -> ForegroundAction.START_DISCOVERY
    }

    fun allowsAutomaticDiscovery(isForeground: Boolean, hasValidPairing: Boolean): Boolean =
        isForeground && !hasValidPairing
}

interface RemoteController {
    val state: StateFlow<RemoteState>
    val discoveredCandidates: StateFlow<List<TvCandidate>>
    val voiceState: StateFlow<VoiceState>

    suspend fun initialize()
    suspend fun enterForeground()
    suspend fun connect(candidate: TvCandidate)
    suspend fun connectRemembered()
    suspend fun submitPairingCode(code: String)
    suspend fun send(command: RemoteCommand, action: RemoteKeyAction = RemoteKeyAction.SHORT)
    suspend fun startVoice()
    suspend fun stopVoice()
    suspend fun disconnect()
    suspend fun forget()
    suspend fun enterBackground()
    fun close()
}
