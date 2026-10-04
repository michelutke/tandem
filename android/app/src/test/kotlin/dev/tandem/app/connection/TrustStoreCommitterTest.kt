package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.trust.PeerRecord
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Instant

class TrustStoreCommitterTest {
    @Test
    fun trustStoreCommitter_commit_putsRecordKeyedBySpkiFingerprintOnly() =
        runTest {
            val stored = mutableListOf<PeerRecord>()
            val fingerprint = SpkiFingerprint(ByteArray(32) { it.toByte() })
            val pairedAt = Instant.ofEpochMilli(1_700_000_000_000)

            TrustStoreCommitter { stored += it }.commit(fingerprint, "Study Mac", pairedAt)

            val record = stored.single()
            assertEquals(fingerprint.base64Url, record.spkiSha256Base64Url)
            assertEquals("Study Mac", record.displayName)
            assertEquals(pairedAt.toEpochMilli(), record.pairedAtEpochMs)
            assertEquals(pairedAt.toEpochMilli(), record.lastSeenEpochMs)
        }
}
