package dev.local.androidtvremote.storage

import android.annotation.SuppressLint
import android.content.Context
import dev.local.androidtvremote.LastTvRecord
import dev.local.androidtvremote.TvDevice
import dev.local.androidtvremote.TvSource
import org.json.JSONObject

class LastTvStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun load(): LastTvRecord? {
        val raw = preferences.getString(KEY_RECORD, null) ?: return null
        return runCatching {
            val json = JSONObject(raw)
            LastTvRecord(
                device = TvDevice(
                    id = json.getString("deviceId"),
                    name = json.getString("deviceName"),
                    source = TvSource.valueOf(json.getString("deviceSource")),
                ),
                lastHost = json.getString("lastHost"),
                bonjourLocatorKey = json.optString("bonjourLocatorKey").takeIf(String::isNotBlank),
                lastConnectedAt = json.getLong("lastConnectedAt"),
                clientIdentityFingerprint = json.getString("clientIdentityFingerprint"),
                pairingPeerFingerprint = json.getString("pairingPeerFingerprint"),
                remotePeerFingerprint = json.getString("remotePeerFingerprint"),
            )
        }.getOrNull()
    }

    @SuppressLint("ApplySharedPref", "UseKtx")
    fun save(record: LastTvRecord) {
        val json = JSONObject()
            .put("deviceId", record.device.id)
            .put("deviceName", record.device.name)
            .put("deviceSource", record.device.source.name)
            .put("lastHost", record.lastHost)
            .put("lastConnectedAt", record.lastConnectedAt)
            .put("clientIdentityFingerprint", record.clientIdentityFingerprint)
            .put("pairingPeerFingerprint", record.pairingPeerFingerprint)
            .put("remotePeerFingerprint", record.remotePeerFingerprint)
        record.bonjourLocatorKey?.let { json.put("bonjourLocatorKey", it) }
        check(preferences.edit().putString(KEY_RECORD, json.toString()).commit()) {
            "Unable to persist the remembered TV"
        }
    }

    @SuppressLint("ApplySharedPref", "UseKtx")
    fun clear() {
        preferences.edit().remove(KEY_RECORD).commit()
    }

    companion object {
        private const val PREFERENCES = "last_tv"
        private const val KEY_RECORD = "record"
    }
}
