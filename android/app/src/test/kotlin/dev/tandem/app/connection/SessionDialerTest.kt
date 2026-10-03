package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.IOException
import java.net.ConnectException
import java.security.cert.CertificateException
import javax.net.ssl.SSLHandshakeException

class SessionDialerTest {
    @Test
    fun classifyDialFailure_certificateExceptionInCauseChain_pinMismatch() {
        val error =
            SSLHandshakeException("handshake failed").apply { initCause(CertificateException("no pin matches")) }

        assertEquals(
            DialResult.PinMismatch(ConnectionFailure.HandshakeError("PIN_MISMATCH")),
            classifyDialFailure(error, wasPreviouslyPinned = true),
        )
    }

    @Test
    fun classifyDialFailure_clientKeyRejectedByPreviouslyPinnedPeer_revoked() {
        val error = SSLHandshakeException("Received fatal alert: certificate_unknown")

        assertEquals(
            DialResult.Unreachable(ConnectionFailure.HandshakeError("REVOKED")),
            classifyDialFailure(error, wasPreviouslyPinned = true),
        )
    }

    @Test
    fun classifyDialFailure_otherHandshakeFailure_sanitizedGenericFailure() {
        val error = SSLHandshakeException("secret detail certificate_unknown")

        assertEquals(
            DialResult.Unreachable(ConnectionFailure.HandshakeError("HANDSHAKE_FAILED")),
            classifyDialFailure(error, wasPreviouslyPinned = false),
        )
    }

    @Test
    fun classifyDialFailure_connectFailure_unreachableWithoutFailure() {
        val refused = classifyDialFailure(ConnectException("refused"), wasPreviouslyPinned = true)
        val reset = classifyDialFailure(IOException("reset"), wasPreviouslyPinned = true)

        assertEquals(DialResult.Unreachable(null), refused)
        assertEquals(DialResult.Unreachable(null), reset)
    }
}
