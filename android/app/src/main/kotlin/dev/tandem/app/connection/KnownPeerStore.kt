package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * This device's own memory of peers it has ever connected to (E20-21), kept apart from the trust
 * store so it survives a revoke: SPEC.md #errors-and-close-codes row 7 maps a failed handshake
 * to `REVOKED` only if this side had previously pinned that peer. One base64url SPKI fingerprint
 * per line; entries are never removed. Never a trust anchor -- trust stays in the trust store.
 * Nothing calls [recordPinned] yet: the dialer that does arrives with E20-05.
 */
class KnownPeerStore(
    private val file: File,
) {
    private val fingerprints: MutableSet<String> =
        (if (file.exists()) file.readLines() else emptyList())
            .filterTo(mutableSetOf()) { it.isNotBlank() }

    @Synchronized
    fun hasEverPinned(fingerprint: SpkiFingerprint): Boolean = fingerprint.base64Url in fingerprints

    @Synchronized
    fun recordPinned(fingerprint: SpkiFingerprint) {
        if (!fingerprints.add(fingerprint.base64Url)) return
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, "${file.name}.tmp")
        temp.writeText(fingerprints.joinToString("\n"))
        Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }
}
