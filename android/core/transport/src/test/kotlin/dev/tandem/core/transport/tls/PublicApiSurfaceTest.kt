package dev.tandem.core.transport.tls

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * E12-04 tdd (D-67):
 *   unit: byteStreamSession_publicSurface_noChannelBindingOrExporterProperty
 *
 * "No public API of this client or its ByteStream session exposes a channel-binding or exporter
 * value" — checked by reflection over each class's own declared public methods (declaring class
 * filter excludes inherited `ByteStream`/`Closeable`/`Object` members).
 */
class PublicApiSurfaceTest {
    @Test
    fun byteStreamSession_publicSurface_noChannelBindingOrExporterProperty() {
        assertNoBannedSurface(SslSocketByteStream::class.java)
    }

    @Test
    fun sslClientFactory_publicSurface_noChannelBindingOrExporterProperty() {
        assertNoBannedSurface(SslClientFactory::class.java)
    }

    private fun assertNoBannedSurface(type: Class<*>) {
        val bannedSubstrings = listOf("channelbinding", "exporter", "keyingmaterial")
        val declaredPublicMemberNames = type.methods.filter { it.declaringClass == type }.map { it.name.lowercase() }

        val offending = declaredPublicMemberNames.filter { name -> bannedSubstrings.any { name.contains(it) } }
        assertTrue(offending.isEmpty(), "Found banned public members on ${type.name}: $offending")
    }
}
