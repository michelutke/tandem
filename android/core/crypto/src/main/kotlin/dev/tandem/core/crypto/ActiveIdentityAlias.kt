package dev.tandem.core.crypto

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

private val VERSIONED_ALIAS = Regex("""^(.*\.v)(\d+)$""")

/**
 * Names the Keystore alias of the phone's active identity key (E70-02). Starts at
 * [IDENTITY_KEY_ALIAS] (every existing install); a completed key rotation [activate]s the new
 * alias, which the TLS key manager reads on every handshake. With a [file] the alias survives
 * restarts: a missing or blank file means [IDENTITY_KEY_ALIAS], and [activate] replaces the file
 * atomically, so a crash leaves either the old or the new alias, never a partial one.
 */
class ActiveIdentityAlias(
    private val file: File? = null,
) {
    @Volatile
    var current: String =
        file
            ?.takeIf { it.isFile }
            ?.readText()
            ?.trim()
            ?.ifEmpty { null } ?: IDENTITY_KEY_ALIAS
        private set

    fun activate(alias: String) {
        file?.let { write(it, alias) }
        current = alias
    }

    /** The alias a rotation away from [current] generates its new key under: `…v1` becomes `…v2`. */
    fun nextAlias(): String {
        val match = VERSIONED_ALIAS.matchEntire(current) ?: return "$current.v2"
        return match.groupValues[1] + (match.groupValues[2].toInt() + 1)
    }

    private fun write(
        target: File,
        alias: String,
    ) {
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeText(alias)
        Files.move(
            temporary.toPath(),
            target.toPath(),
            StandardCopyOption.ATOMIC_MOVE,
            StandardCopyOption.REPLACE_EXISTING,
        )
    }
}
