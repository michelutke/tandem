package dev.tandem.core.transport

import javax.net.ssl.SSLException

/**
 * The TLS alerts a peer sends when it rejects this phone's client certificate (RFC 8446 section 6.2,
 * TLS 1.3 reports them after the handshake completes on the client). Platform TLS stacks only expose
 * the alert name in an [SSLException]'s message, so this is the one place a name is matched.
 */
object ClientCertificateAlerts {
    val NAMES =
        listOf(
            "certificate_unknown",
            "bad_certificate",
            "certificate_required",
            "unknown_ca",
            "access_denied",
        )

    /** `true` if [failure] or anything in its cause chain is an [SSLException] naming one of [NAMES]. */
    fun isRejection(failure: Throwable): Boolean =
        generateSequence(failure) { it.cause }
            .filterIsInstance<SSLException>()
            .any { exception -> NAMES.any { exception.message.orEmpty().contains(it, ignoreCase = true) } }
}
