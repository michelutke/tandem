package dev.tandem.core.transport.tls

import dev.tandem.core.transport.testserver.AcceptAnyTrustManager
import dev.tandem.core.transport.testserver.TestIdentity
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Test

/**
 * E12-04 tdd:
 *   unit: sslClientFactory_createdSocket_enabledProtocolsExactlyTls13
 */
class SslClientFactoryTest {
    @Test
    fun sslClientFactory_createdSocket_enabledProtocolsExactlyTls13() {
        val identity = TestIdentity(alias = "client")
        val factory = SslClientFactory(identity.keyManager, AcceptAnyTrustManager(), ConscryptSessionTicketDisabler())

        factory.createSocket().use { socket ->
            assertArrayEquals(arrayOf("TLSv1.3"), socket.enabledProtocols)
        }
    }
}
