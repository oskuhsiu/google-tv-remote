package dev.local.androidtvremote

import dev.local.androidtvremote.storage.persistRecordWithRollback
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class RecordPersistenceTests {
    @Test
    fun `failed disk commit restores old record already changed in memory`() {
        var memory: String? = "previous-client-fingerprint"
        val writes = mutableListOf<String?>()
        assertThrows(IllegalStateException::class.java) {
            persistRecordWithRollback("new-client-fingerprint", memory) { value ->
                memory = value // SharedPreferences publishes this before disk commit.
                writes += value
                false
            }
        }
        assertEquals("previous-client-fingerprint", memory)
        assertEquals(listOf("new-client-fingerprint", "previous-client-fingerprint"), writes)
    }

    @Test
    fun `failed first save removes the incomplete record from memory`() {
        var memory: String? = null
        assertThrows(IllegalStateException::class.java) {
            persistRecordWithRollback("new-client-fingerprint", memory) { value -> memory = value; false }
        }
        assertNull(memory)
    }

    @Test
    fun `successful save publishes the record once`() {
        var memory: String? = "previous-client-fingerprint"
        var writes = 0
        persistRecordWithRollback("new-client-fingerprint", memory) { value -> memory = value; writes++; true }
        assertEquals("new-client-fingerprint", memory)
        assertEquals(1, writes)
    }

    @Test
    fun `writer exception after publication also restores the prior record`() {
        var memory: String? = "previous-client-fingerprint"
        var writes = 0
        assertThrows(IllegalStateException::class.java) {
            persistRecordWithRollback("new-client-fingerprint", memory) { value ->
                memory = value
                if (writes++ == 0) throw IllegalStateException("Disk write failed")
                true
            }
        }
        assertEquals("previous-client-fingerprint", memory)
        assertEquals(2, writes)
    }
}
