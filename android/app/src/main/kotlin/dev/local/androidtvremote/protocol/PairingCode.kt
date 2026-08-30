package dev.local.androidtvremote.protocol

@JvmInline
value class PairingCode private constructor(val value: String) {
    companion object {
        private val pattern = Regex("[0-9A-F]{6}")

        fun parse(raw: String): PairingCode? {
            val normalized = raw.trim().uppercase()
            return normalized.takeIf(pattern::matches)?.let(::PairingCode)
        }
    }
}

