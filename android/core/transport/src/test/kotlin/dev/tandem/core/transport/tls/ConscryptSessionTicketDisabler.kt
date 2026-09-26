package dev.tandem.core.transport.tls

import javax.net.ssl.SSLSocket

/**
 * JVM test-only stand-in for [AndroidSessionTicketDisabler]: `android.net.ssl.SSLSockets` is
 * Android-only and its stub throws on a bare JVM test classpath, so `integration:` tests exercise
 * this Conscrypt-native equivalent instead (`org.conscrypt:conscrypt-openjdk-uber`,
 * `testImplementation`-only, never on a production classpath).
 */
class ConscryptSessionTicketDisabler : SessionTicketDisabler {
    override fun disable(socket: SSLSocket) {
        org.conscrypt.Conscrypt.setUseSessionTickets(socket, false)
    }
}
