package dev.tandem.core.transport.tls

import android.net.ssl.SSLSockets
import javax.net.ssl.SSLSocket

/**
 * Disables TLS session ticket resumption on a not-yet-connected [SSLSocket] (E12-04, SPEC.md
 * "TLS version and cipher profile": the client MUST use a fresh `SSLContext` per connection and
 * MUST disable session tickets on it, so it never even offers a PSK identity). Injected so a JVM
 * `integration:` test can substitute Conscrypt's own equivalent call (`org.conscrypt.Conscrypt`,
 * `core/transport`'s `test` source set), since `android.net.ssl.SSLSockets` is Android-only and
 * unusable on a bare JVM test classpath.
 */
fun interface SessionTicketDisabler {
    fun disable(socket: SSLSocket)
}

/** Production default: the platform's public wrapper over its built-in Conscrypt provider (ADR-003). */
class AndroidSessionTicketDisabler : SessionTicketDisabler {
    override fun disable(socket: SSLSocket) {
        SSLSockets.setUseSessionTickets(socket, false)
    }
}
