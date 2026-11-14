package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.revoke.TrustRemover
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class RevokedNoticeStoreTest {
    @Test
    fun revokedNoticeStore_freshFile_noName(
        @TempDir directory: File,
    ) {
        assertNull(RevokedNoticeStore(File(directory, "notice")).macName.value)
    }

    @Test
    fun revokedNoticeStore_markThenNewInstance_namePersistsUntilCleared(
        @TempDir directory: File,
    ) {
        val file = File(directory, "notice")
        RevokedNoticeStore(file).mark("MacBook Pro")

        val reopened = RevokedNoticeStore(file)
        assertEquals("MacBook Pro", reopened.macName.value)

        reopened.clear()

        assertNull(reopened.macName.value)
        assertNull(RevokedNoticeStore(File(file.path)).macName.value)
    }

    @Test
    fun noticingTrustRemover_remove_marksTheNameThenDelegates(
        @TempDir directory: File,
    ) = runTest {
        val store = RevokedNoticeStore(File(directory, "notice"))
        val removed = mutableListOf<SpkiFingerprint>()
        val peer = SpkiFingerprint(ByteArray(32) { 3 })

        NoticingTrustRemover(
            macName = { if (it == peer) "MacBook Pro" else null },
            notice = store,
            delegate = TrustRemover { removed += it },
        ).remove(peer)

        assertEquals("MacBook Pro", store.macName.value)
        assertEquals(listOf(peer), removed)
    }

    @Test
    fun noticingTrustRemover_delegateFails_noNoticeMarked(
        @TempDir directory: File,
    ) = runTest {
        val store = RevokedNoticeStore(File(directory, "notice"))

        runCatching {
            NoticingTrustRemover(
                macName = { "MacBook Pro" },
                notice = store,
                delegate = TrustRemover { error("boom") },
            ).remove(SpkiFingerprint(ByteArray(32)))
        }

        assertNull(store.macName.value)
    }

    @Test
    fun noticingTrustRemover_nameLookupFails_trustStillRemovedWithEmptyName(
        @TempDir directory: File,
    ) = runTest {
        val store = RevokedNoticeStore(File(directory, "notice"))
        val removed = mutableListOf<SpkiFingerprint>()
        val peer = SpkiFingerprint(ByteArray(32) { 3 })

        NoticingTrustRemover(
            macName = { error("trust store unreadable") },
            notice = store,
            delegate = TrustRemover { removed += it },
        ).remove(peer)

        assertEquals(listOf(peer), removed)
        assertEquals("", store.macName.value)
    }
}
