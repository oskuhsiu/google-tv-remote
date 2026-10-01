package dev.local.androidtvremote.discovery

internal data class RememberedTvService(val locatorKey: String, val name: String) {
    companion object {
        fun parse(locatorKey: String?): RememberedTvService? {
            val parts = locatorKey?.split('|', limit = 3) ?: return null
            if (parts.size != 3 || parts[0] != "local." ||
                parts[1].removePrefix(".").removeSuffix(".") != TvDiscovery.SERVICE_TYPE ||
                parts[2].isBlank()
            ) return null
            return RememberedTvService(locatorKey, parts[2])
        }
    }
}
