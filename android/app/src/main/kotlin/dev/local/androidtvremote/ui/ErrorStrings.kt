package dev.local.androidtvremote.ui

import androidx.annotation.StringRes
import dev.local.androidtvremote.R
import dev.local.androidtvremote.RemoteError

@StringRes
fun RemoteError.messageResource(): Int = when (this) {
    RemoteError.NETWORK_UNREACHABLE -> R.string.error_network_unreachable
    RemoteError.TV_NOT_FOUND -> R.string.error_tv_not_found
    RemoteError.PAIRING_REQUIRED -> R.string.error_pairing_required
    RemoteError.PAIRING_CODE_INVALID -> R.string.error_pairing_code_invalid
    RemoteError.PAIRING_REJECTED -> R.string.error_pairing_rejected
    RemoteError.PAIRING_TIMEOUT -> R.string.error_pairing_timeout
    RemoteError.TRUST_CHANGED -> R.string.error_trust_changed
    RemoteError.CONNECTION_LOST -> R.string.error_connection_lost
    RemoteError.VOICE_PERMISSION_DENIED -> R.string.error_voice_permission_denied
    RemoteError.VOICE_SESSION_FAILED -> R.string.error_voice_session_failed
    RemoteError.TEXT_INPUT_FAILED -> R.string.error_text_input_failed
    RemoteError.UNKNOWN -> R.string.error_unknown
}

