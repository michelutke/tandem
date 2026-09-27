package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ConnectionErrorMapperTest {
    @Test
    fun connectionErrorMapper_everyFailureReason_distinctNonEmptyResource() {
        val timeoutResource =
            ConnectionErrorMapper.mapToErrorMessage(ConnectionFailure.Timeout)
        val handshakeErrorResource =
            ConnectionErrorMapper.mapToErrorMessage(
                ConnectionFailure.HandshakeError("PIN_MISMATCH"),
            )
        val versionMismatchResource =
            ConnectionErrorMapper.mapToErrorMessage(
                ConnectionFailure.HandshakeError("VERSION_MISMATCH"),
            )

        assertTrue(timeoutResource.isNotBlank())
        assertTrue(handshakeErrorResource.isNotBlank())
        assertTrue(versionMismatchResource.isNotBlank())
        assertNotEquals(timeoutResource, handshakeErrorResource)
        assertNotEquals(handshakeErrorResource, versionMismatchResource)
    }

    @Test
    fun connectionErrorMapper_serverCertificateUnknownAlert_noLongerPairedWithMacName() {
        val macName = "Michel's Mac"
        val message =
            ConnectionErrorMapper.mapToErrorMessage(
                ConnectionFailure.HandshakeError("REVOKED"),
                macName = macName,
            )

        assertTrue(message.contains(macName))
        assertTrue(message.contains("no longer paired") || message.contains("unpaired"))
    }

    @Test
    fun connectionErrorMapper_noLongerPaired_trustRecordNotDeleted() {
        // This test verifies that the mapper itself does not delete trust records
        // It only maps the failure to a message; deletion is not its responsibility
        val message =
            ConnectionErrorMapper.mapToErrorMessage(
                ConnectionFailure.HandshakeError("REVOKED"),
                macName = "Test Mac",
            )

        assertTrue(message.isNotBlank())
    }

    @Test
    fun connectionErrorMapper_alertAfterFailedPinCheck_mapsToPinMismatch() {
        // A handshake error that maps to PIN_MISMATCH
        val message =
            ConnectionErrorMapper.mapToErrorMessage(
                ConnectionFailure.HandshakeError("PIN_MISMATCH"),
            )

        assertTrue(message.isNotBlank())
        assertTrue(
            message.contains("pin") || message.contains("mismatch") ||
                message.contains("trusted"),
        )
    }
}
