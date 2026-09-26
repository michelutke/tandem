package dev.tandem.harness.jvmclient

import dev.tandem.core.transport.tls.SessionTicketDisabler
import org.conscrypt.Conscrypt
import java.security.Security
import javax.net.ssl.SSLSocket

/**
 * Installs Conscrypt as the JVM's highest-priority security provider (E15-21; mirrors Android's
 * own built-in Conscrypt, ADR-003): a bare `SSLContext.getInstance("TLSv1.3")` — exactly what
 * `SslClientFactory.createSocket` calls — otherwise resolves to the JDK's built-in SunJSSE.
 * Referencing this object is enough to run its `init` block exactly once per JVM.
 */
object HarnessConscryptProvider {
    init {
        Security.insertProviderAt(Conscrypt.newProvider(), 1)
    }

    fun ensureInstalled() = Unit
}

/**
 * [SessionTicketDisabler] for the JVM harness (E15-21): `AndroidSessionTicketDisabler`
 * (`SslClientFactory`'s default) calls `android.net.ssl.SSLSockets`, an Android-only class absent
 * from a bare JVM classpath (`NoClassDefFoundError`); this calls Conscrypt's own equivalent
 * directly instead, the same way `core/transport`'s own `integration:` tests do (its test-only
 * `ConscryptSessionTicketDisabler`) — except here it is production code, since this whole harness
 * client runs on a bare JVM, never Android.
 */
class JvmConscryptSessionTicketDisabler : SessionTicketDisabler {
    override fun disable(socket: SSLSocket) {
        HarnessConscryptProvider.ensureInstalled()
        Conscrypt.setUseSessionTickets(socket, false)
    }
}
