package dev.local.androidtvremote.storage

internal fun persistRecordWithRollback(value: String, previous: String?, write: (String?) -> Boolean) {
    val failure = try {
        if (write(value)) return
        IllegalStateException("Unable to persist the remembered TV")
    } catch (error: Exception) {
        error
    }
    // SharedPreferences publishes to memory before its disk commit result.
    // Even a failed rollback write restores the previous in-memory value.
    runCatching { write(previous) }
    throw failure
}
