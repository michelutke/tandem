package dev.tandem.feature.clipboard

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
    fun clipboardSender_exactly1MiB_sends() =
        runTest {
            val session = FakeTandemSession()
            val exactText = "a".repeat(ClipboardSender.MAX_TEXT_BYTES)

            val sent = ClipboardSender.send(exactText, session)

            assertTrue(sent)
            assertEquals(1, session.sentFrames.size)
        }
}
