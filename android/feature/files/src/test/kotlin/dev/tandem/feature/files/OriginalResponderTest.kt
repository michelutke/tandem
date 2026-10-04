package dev.tandem.feature.files

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.PhotoErrorKind
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.originalRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.security.MessageDigest

// E41-07 tdd (docs/planning/backlog/phase-4.yaml): FakeTandemSession + fake MediaStoreSource with fixture bytes.
@OptIn(ExperimentalCoroutinesApi::class)
class OriginalResponderTest {
    private val session = FakeTandemSession()
    private val fixtureBytes = "original-bytes".toByteArray()

    private val source =
        object : MediaStoreSource {
            override fun query(
                after: MediaKey?,
                limit: Int,
            ): List<MediaRow> = emptyList()

            override fun item(id: Long): MediaItem? =
                when (id) {
                    KNOWN_ID -> MediaItem("content://media/$id", "IMG_0001.jpg", "image/jpeg")
                    DENIED_ID -> throw SecurityException()
                    else -> null
                }
        }

    @Test
    fun originalRequest_knownId_fileOfferWithTransferIdAndFixtureSha256() =
        runTest {
            val outcome = responder().respond(request(KNOWN_ID.toString()))
            runCurrent()

            assertTrue(outcome is OriginalOutcome.Started)
            val offers = session.sentFrames.filter { it.hasFileOffer() }.map { it.fileOffer }
            assertEquals(1, offers.size)
            assertEquals(TRANSFER_ID, offers.single().id)
            assertEquals("IMG_0001.jpg", offers.single().name)
            assertEquals(
                sha256(fixtureBytes).toList(),
                offers
                    .single()
                    .sha256
                    .toByteArray()
                    .toList(),
            )
        }

    @Test
    fun originalRequest_unknownId_notFoundErrorAndNoOffer() =
        runTest {
            val outcome = responder().respond(request("999"))
            runCurrent()

            val error = (outcome as OriginalOutcome.Failure).error
            assertEquals(PhotoErrorKind.PHOTO_ERROR_KIND_ORIGINAL, error.kind)
            assertEquals("999", error.ref)
            assertEquals(PhotoErrorReason.PHOTO_ERROR_REASON_NOT_FOUND, error.reason)
            assertTrue(session.sentFrames.none { it.hasFileOffer() })
        }

    @Test
    fun originalRequest_idOutsidePartialGrant_accessDeniedErrorAndNoOffer() =
        runTest {
            val outcome = responder().respond(request(DENIED_ID.toString()))
            runCurrent()

            val error = (outcome as OriginalOutcome.Failure).error
            assertEquals(PhotoErrorKind.PHOTO_ERROR_KIND_ORIGINAL, error.kind)
            assertEquals(PhotoErrorReason.PHOTO_ERROR_REASON_ACCESS_DENIED, error.reason)
            assertTrue(session.sentFrames.none { it.hasFileOffer() })
        }

    private fun request(id: String) =
        originalRequest {
            this.id = id
            transferId = TRANSFER_ID
        }

    private fun TestScope.responder(): OriginalResponder {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val sender =
            FileSender(
                session,
                FilesScheduler(session, dispatcher),
                { ByteArrayInputStream(fixtureBytes) },
                StandardTestDispatcher(testScheduler),
                dispatcher,
            )
        return OriginalResponder(source, sender)
    }

    private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

    private companion object {
        const val KNOWN_ID = 42L
        const val DENIED_ID = 7L
        const val TRANSFER_ID = "transfer-1"
    }
}
