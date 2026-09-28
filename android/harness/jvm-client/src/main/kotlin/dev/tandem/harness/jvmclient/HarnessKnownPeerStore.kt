package dev.tandem.harness.jvmclient

import java.io.File

/**
 * Tiny on-disk stand-in (E14-20) for the JVM harness client's own persisted knowledge of peers it
 * has connected to, kept next to `--identity-file` the same way [PersistentIdentityKeyStore]
 * persists the identity itself -- the harness has no real client-side `TrustStore` of its own
 * (E15-21 harness scope), but proving `docs/protocol/SPEC.md` #errors-and-close-codes row 7's
 * `REVOKED`-vs-`PIN_MISMATCH` mapping ("if this side had previously pinned that peer") across a JVM
 * client process restart (`jvmHarness_macRevokesOfflinePhone_nextHandshakeFailsNoLongerPaired`) needs
 * that one bit of knowledge to survive the restart. One hex SPKI fingerprint per line; entries are
 * never removed -- nothing in this harness's scope needs that, and D-23's "no persistent revoked
 * record" note is about the *rejecting* side's trust store, not the dialing side's own memory of
 * what it once successfully connected to.
 */
class HarnessKnownPeerStore(identityFile: File) {
    private val file = File(identityFile.absoluteFile.parentFile, "${identityFile.name}.known-peers")
    private val hexFingerprints: MutableSet<String> =
        (if (file.exists()) file.readLines() else emptyList())
            .filterTo(mutableSetOf()) { it.isNotBlank() }

    /** Whether this identity has ever reached `OK CONNECTED` against [fingerprintHex] before. */
    fun hasEverPinned(fingerprintHex: String): Boolean = fingerprintHex in hexFingerprints

    /** Records that this identity just reached `OK CONNECTED` against [fingerprintHex]. */
    fun recordPinned(fingerprintHex: String) {
        if (hexFingerprints.add(fingerprintHex)) {
            file.parentFile?.mkdirs()
            file.writeText(hexFingerprints.joinToString("\n"))
        }
    }
}
