package dev.tandem.feature.files

import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.fileOffer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.seconds

// E40-07 tdd (docs/planning/backlog/phase-4.yaml). The 300 s timeout runs on virtual time shared
// with TestClock via the same testScheduler (E00-18).
@OptIn(ExperimentalCoroutinesApi::class)
class AcceptFlowTest {
    private val session = FakeTandemSession()
    private val freeSpace = FakeFreeSpace(Long.MAX_VALUE)
    private val prompter = FakePrompter()
    private var settings = AcceptSettings()
    private var active = 0

    @Test
    fun androidAcceptFlow_freeSpaceBelowSizePlusReserve_insufficientSpaceRejectNoPrompt() =
        runTest {
            freeSpace.bytes = MIB + RESERVE - 1
            newFlow()

            offer("a", size = MIB)

            assertEquals(listOf("a" to TransferReason.TRANSFER_REASON_INSUFFICIENT_SPACE), rejects())
            assertTrue(prompter.posted.isEmpty())
        }

    @Test
    fun androidAcceptFlow_autoAcceptOn_fileAcceptSentWithoutPrompt() =
        runTest {
            settings = AcceptSettings(autoAccept = true)
            newFlow()

            offer("a", size = MIB)

            assertEquals(listOf("a"), session.sentFrames.map { it.fileAccept.id })
            assertTrue(prompter.posted.isEmpty())
        }

    @Test
    fun androidAcceptFlow_acceptTapped_fileAcceptSentAndPromptCancelled() =
        runTest {
            val flow = newFlow()
            offer("a", size = MIB)
            assertTrue(session.sentFrames.isEmpty())

            flow.accept("a")
            runCurrent()

            assertEquals(listOf("a"), session.sentFrames.map { it.fileAccept.id })
            assertEquals(listOf("a"), prompter.cancelled)
        }

    @Test
    fun androidAcceptFlow_declineTapped_fileRejectDeclinedSent() =
        runTest {
            val flow = newFlow()
            offer("a", size = MIB)

            flow.decline("a")
            runCurrent()

            assertEquals(listOf("a" to TransferReason.TRANSFER_REASON_DECLINED), rejects())
            advanceTimeBy(301.seconds)
            assertEquals(1, session.sentFrames.size)
        }

    @Test
    fun androidAcceptFlow_noAnswerFor300s_timeoutRejectAndPromptCancelled() =
        runTest {
            newFlow()
            offer("a", size = MIB)

            advanceTimeBy(299.seconds)
            assertTrue(session.sentFrames.isEmpty())
            advanceTimeBy(2.seconds)

            assertEquals(listOf("a" to TransferReason.TRANSFER_REASON_TIMEOUT), rejects())
            assertEquals(listOf("a"), prompter.cancelled)
            assertEquals(301_000L, TestClock(testScheduler).millis())
        }

    @Test
    fun androidAcceptFlow_autoAcceptOnOfferOver1GiB_promptShown() =
        runTest {
            settings = AcceptSettings(autoAccept = true)
            newFlow()

            offer("a", size = GIB + 1)

            assertEquals(listOf("a"), prompter.posted.map { it.id })
            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun androidAcceptFlow_fifthPendingOffer_busyRejectNoPrompt() =
        runTest {
            newFlow()

            repeat(4) { offer("p$it", size = MIB) }
            offer("fifth", size = MIB)

            assertEquals(listOf("fifth" to TransferReason.TRANSFER_REASON_BUSY), rejects())
            assertEquals(4, prompter.posted.size)
        }

    @Test
    fun androidAcceptFlow_twoActiveTransfers_busyRejectNoPrompt() =
        runTest {
            active = 2
            newFlow()

            offer("a", size = MIB)

            assertEquals(listOf("a" to TransferReason.TRANSFER_REASON_BUSY), rejects())
            assertTrue(prompter.posted.isEmpty())
        }

    @Test
    fun androidAcceptFlow_offerOver64GiB_tooLargeReject() =
        runTest {
            newFlow()

            offer("a", size = (1L shl 36) + 1)

            assertEquals(listOf("a" to TransferReason.TRANSFER_REASON_TOO_LARGE), rejects())
            assertTrue(prompter.posted.isEmpty())
        }

    @Test
    fun androidAcceptFlow_hostileName_promptShowsSanitizedName() =
        runTest {
            newFlow()

            offer("a", size = MIB, name = "evil‮txt.exe\u0000")

            assertEquals("eviltxt.exe", prompter.posted.single().name)
        }

    private fun TestScope.newFlow(): AcceptFlow =
        AcceptFlow(session, freeSpace, prompter, { settings }, { active }, StandardTestDispatcher(testScheduler))

    private fun TestScope.offer(
        id: String,
        size: Long,
        name: String = "f.txt",
    ) {
        runCurrent()
        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_FILES
                fileOffer =
                    fileOffer {
                        this.id = id
                        this.name = name
                        this.size = size
                    }
            },
        )
        runCurrent()
    }

    private fun rejects() =
        session.sentFrames.filter { it.hasFileReject() }.map { it.fileReject.id to it.fileReject.reason }

    private class FakeFreeSpace(
        var bytes: Long,
    ) : FreeSpaceProvider {
        override fun freeBytes(): Long = bytes
    }

    private class FakePrompter : TransferPrompter {
        data class Posted(
            val id: String,
            val name: String,
            val size: Long,
        )

        val posted = mutableListOf<Posted>()
        val cancelled = mutableListOf<String>()

        override fun post(
            offerId: String,
            displayName: String,
            sizeBytes: Long,
        ) {
            posted += Posted(offerId, displayName, sizeBytes)
        }

        override fun cancel(offerId: String) {
            cancelled += offerId
        }
    }

    private companion object {
        const val MIB = 1L shl 20
        const val GIB = 1L shl 30
        const val RESERVE = 64L * MIB
    }
}
