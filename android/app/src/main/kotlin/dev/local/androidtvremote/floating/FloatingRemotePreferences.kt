package dev.local.androidtvremote.floating

import android.content.Context
import androidx.core.content.edit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class FloatingRemotePreferences(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val mutableEnabled = MutableStateFlow(preferences.getBoolean(KEY_ENABLED, false))

    val enabled: StateFlow<Boolean> = mutableEnabled.asStateFlow()

    fun setEnabled(enabled: Boolean) {
        if (mutableEnabled.value == enabled) return
        preferences.edit { putBoolean(KEY_ENABLED, enabled) }
        mutableEnabled.value = enabled
    }

    private companion object {
        const val PREFERENCES_NAME = "floating_remote"
        const val KEY_ENABLED = "enabled"
    }
}
