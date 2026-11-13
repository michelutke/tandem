package dev.tandem.feature.clipboard

import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.MessageDigest

/**
 * ClipboardSender E31-06 tests (`docs/planning/backlog/phase-3.yaml` E31-06's `tdd:` list). Plain
 * JUnit5 (CLAUDE.md's Robolectric rule): [ClipboardSender] touches no Android framework type,
 * only [dev.tandem.core.transport.TandemSession] (scripted via [FakeTandemSession], E12-11).
 */
class ClipboardSenderTest {
    @Test
    fun clipboardSender_withinCap_sendsClipboardTextOriginAndroidWithSha256Hash() =
        runTest {
            val session = FakeTandemSession()

            val sent = ClipboardSender.send("hello mac", session)

            assertTrue(sent)
            val frame = session.sentFrames.single().clipboardText
            assertEquals("android", frame.originTag)
            assertEquals("hello mac", frame.text)
            val expectedHash = MessageDigest.getInstance("SHA-256").digest("hello mac".toByteArray(Charsets.UTF_8))
            assertEquals(expectedHash.toList(), frame.contentHash.toByteArray().toList())
        }

    @Test
    fun clipboardSender_oneByteOver1MiB_noFrameAndTooLargeToast() =
        runTest {
            val session = FakeTandemSession()
            val oversizeText = "a".repeat(ClipboardSender.MAX_TEXT_BYTES + 1)
            var toastShown = false

            val sent = ClipboardSender.send(oversizeText, session, onTooLarge = { toastShown = true })

            assertFalse(sent)
            assertTrue(session.sentFrames.isEmpty())
            assertTrue(toastShown)
        }

    @Test
    fun clipboardSender_exactlyCap_sendsAndFrameFitsEnvelopeLimit() =
        runTest {
            val session = FakeTandemSession()
            val exactText = "a".repeat(ClipboardSender.MAX_TEXT_BYTES)

            val sent = ClipboardSender.send(exactText, session, sensitive = true)

            assertTrue(sent)
            assertEquals(1, session.sentFrames.size)
            val worstCaseFrame =
                session.sentFrames
                    .single()
                    .toBuilder()
                    .setSeq(Long.MAX_VALUE)
                    .setAck(Long.MAX_VALUE)
                    .build()
            val framed = FrameEncoder.encodeFrame(worstCaseFrame)
            assertTrue(framed.size - 4 <= FrameEncoder.MAX_ENVELOPE_BYTES)
        }

    @Test
    fun clipboardSender_textAtCapPlusEnvelopeOverhead_rejectedBeforeSend() =
        runTest {
            val session = FakeTandemSession()
            val nearLimitText = "a".repeat(FrameEncoder.MAX_ENVELOPE_BYTES - OVERHEAD_BELOW_LIMIT)
            var toastShown = false

            val sent = ClipboardSender.send(nearLimitText, session, onTooLarge = { toastShown = true })

            assertFalse(sent)
            assertTrue(session.sentFrames.isEmpty())
            assertTrue(toastShown)
        }

    private companion object {
        const val OVERHEAD_BELOW_LIMIT = 10
    }
}
