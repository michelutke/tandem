package dev.tandem.core.protocol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** FilenameSanitizer E40-16 tests (`docs/planning/backlog/phase-4.yaml` E40-16's `tdd:` list). Plain JUnit5. */
class FilenameSanitizerTest {
    private val transferId = "1a2b3c4d5e6f4a7b8c9d0e1f2a3b4c5d"

    @Test
    fun androidFilenameSanitizer_pathTraversal_lastComponentOnly() {
        assertEquals("passwd", FilenameSanitizer.sanitize("../../etc/passwd", transferId))
        assertEquals("evil.exe", FilenameSanitizer.sanitize("C:\\Windows\\evil.exe", transferId))
    }

    @Test
    fun androidFilenameSanitizer_nulByte_invalidName() {
        assertNull(FilenameSanitizer.sanitize("a\u0000b.txt", transferId))
    }

    @Test
    fun androidFilenameSanitizer_dotDot_generatedNameFromTransferId() {
        assertEquals("file-1a2b3c4d", FilenameSanitizer.sanitize("..", transferId))
    }

    @Test
    fun androidFilenameSanitizer_stemOver255Bytes_truncatedTo255BytesKeepingExtension() {
        val result = FilenameSanitizer.sanitize("a".repeat(300) + ".pdf", transferId)

        assertEquals("a".repeat(251) + ".pdf", result)
        assertEquals(255, result!!.toByteArray(Charsets.UTF_8).size)
    }

    @Test
    fun androidFilenameSanitizer_reservedStem_prefixedWithUnderscore() {
        assertEquals("_con.txt", FilenameSanitizer.sanitize("con.txt", transferId))
    }

    @Test
    fun androidFilenameSanitizer_bidiAndControls_removedOrReplaced() {
        assertEquals("ab_c_d.txt", FilenameSanitizer.sanitize("a\u202Eb\u0001c:d.txt", transferId))
    }
}
