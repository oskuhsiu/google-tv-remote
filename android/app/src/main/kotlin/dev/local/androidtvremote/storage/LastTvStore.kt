package dev.local.androidtvremote.storage

import android.annotation.SuppressLint
import android.content.Context
import dev.local.androidtvremote.LastTvRecord
import dev.local.androidtvremote.TvDevice
import dev.local.androidtvremote.TvSource
import dev.local.androidtvremote.wol.WolPacket
import org.json.JSONObject

class LastTvStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun load(): LastTvRecord? {
        val raw = preferences.getString(KEY_RECORD, null) ?: return null
        return runCatching {
            val json = JSONObject(raw)
            val rawMac = json.optString("macAddress")
            val macAddress = rawMac.takeIf { it.isNotBlank() && it != "null" }
                ?.let { if (WolPacket.isValidMac(it)) WolPacket.formatMac(it) else null }
            val bonjourLocatorKey = json.optString("bonjourLocatorKey").takeIf { it.isNotBlank() && it != "null" }
            LastTvRecord(
                device = TvDevice(
                    id = json.getString("deviceId"),
                    name = json.getString("deviceName"),
                    source = TvSource.valueOf(json.getString("deviceSource")),
                    macAddress = macAddress,
                ),
                lastHost = json.getString("lastHost"),
                bonjourLocatorKey = bonjourLocatorKey,
                lastConnectedAt = json.getLong("lastConnectedAt"),
                clientIdentityFingerprint = json.getString("clientIdentityFingerprint"),
                pairingPeerFingerprint = json.getString("pairingPeerFingerprint"),
                remotePeerFingerprint = json.getString("remotePeerFingerprint"),
                macAddress = macAddress,
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
        record.macAddress?.let { json.put("macAddress", it) }
        persistRecordWithRollback(json.toString(), preferences.getString(KEY_RECORD, null)) { raw ->
            val editor = preferences.edit()
            if (raw == null) editor.remove(KEY_RECORD) else editor.putString(KEY_RECORD, raw)
            editor.commit()
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
