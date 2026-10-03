package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class KnownPeerStoreTest {
    @TempDir
    lateinit var dir: File

    @Test
    fun knownPeerStore_recordedPeerAfterReopen_hasEverPinned() {
        val file = File(dir, "known-peers")
        val fingerprint = SpkiFingerprint(ByteArray(32) { 1 })
        KnownPeerStore(file).recordPinned(fingerprint)

        assertTrue(KnownPeerStore(file).hasEverPinned(fingerprint))
    }

    @Test
    fun knownPeerStore_unrecordedPeer_neverPinned() {
        val store = KnownPeerStore(File(dir, "known-peers"))

        assertFalse(store.hasEverPinned(SpkiFingerprint(ByteArray(32) { 2 })))
    }
}
