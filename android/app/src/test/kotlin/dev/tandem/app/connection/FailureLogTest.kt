package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FailureLogTest {
    @Test
    fun failureLog_pinMismatch_containsCategoryButNoCertBytes() {
        val failure = ConnectionFailure.HandshakeError("PIN_MISMATCH")
        val logEntry = FailureLogger.formatLogEntry(failure)

        assertTrue(logEntry.contains("PIN_MISMATCH"))
        assertFalse(logEntry.contains("-----BEGIN")) // No PEM-encoded cert
        assertFalse(logEntry.contains("MIIBkjCB")) // No base64 cert bytes
        assertFalse(logEntry.contains("0x")) // No hex bytes
    }
}
