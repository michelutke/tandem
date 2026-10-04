package dev.tandem.app.connection

import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.reconnect.PairingAddressSource
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The addresses the QR payload listed at pairing time (E20-24), one `port host` line each, as a
 * candidate source for the reconnect loop. A hint only: it never decides trust (invariant 3), the
 * pinned mTLS handshake does.
 */
class PairingAddressStore(
    private val file: File,
) : PairingAddressSource {
    @Synchronized
    fun save(
        addresses: List<String>,
        port: Int,
    ) {
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, "${file.name}.tmp")
        temp.writeText(addresses.joinToString("\n") { "$port $it" })
        Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    @Synchronized
    fun clear() {
        file.delete()
    }

    @Synchronized
    override fun addresses(): List<CandidateAddress> =
        if (file.exists()) file.readLines().mapNotNull(::parse) else emptyList()

    private fun parse(line: String): CandidateAddress? {
        val port = line.substringBefore(' ').toIntOrNull()
        val host = line.substringAfter(' ', "").takeIf { it.isNotBlank() }
        return if (port != null && host != null) CandidateAddress(host, port) else null
    }
}
