package dev.tandem.core.transport.testserver

import org.conscrypt.Conscrypt
import java.security.Security

/**
 * Installs Conscrypt as the JVM's highest-priority security provider, once per test JVM. Without
 * this, a bare `SSLContext.getInstance("TLSv1.3")` (no explicit provider argument — exactly what
 * `SslClientFactory` calls in production) resolves to the JDK's built-in SunJSSE, not Conscrypt,
 * so the same production client code can't be exercised against Conscrypt-specific behavior (its
 * ALPN/ticket handling, and `ConscryptSessionTicketDisabler`, which requires an actual Conscrypt
 * socket instance) the way it runs against Android's built-in Conscrypt provider (ADR-003).
 */
object ConscryptProviderInstaller {
    init {
        Security.insertProviderAt(Conscrypt.newProvider(), 1)
    }

    /** No-op body: referencing this object is enough to run [init] exactly once. */
    fun ensureInstalled() = Unit
}
