package dev.tandem.feature.files

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.protocol.v1.PhotoErrorKind
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.thumbRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode
import java.io.FileNotFoundException

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ThumbnailResponderTest {
    private val requestedSizes = mutableListOf<Int>()

    private fun responder(loader: ThumbnailLoader = fakeLoader()) =
        ThumbnailResponder(loader, UnconfinedTestDispatcher())

    private fun fakeLoader(
        width: Int = 1000,
        height: Int = 750,
    ) = ThumbnailLoader { _, sizePx ->
        requestedSizes += sizePx
        Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    }

    private fun decode(bytes: ByteArray): Bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))

    @Test
    fun thumbGeneration_maxPx256_longestEdgeAtMost256() =
        runTest {
            val outcome =
                responder().respond(
                    thumbRequest {
                        id = "7"
                        maxPx = 256
                    },
                )

            val result = (outcome as ThumbOutcome.Thumb).result
            val decoded = decode(result.pngBytes.toByteArray())
            assertEquals("7", result.id)
            assertTrue(maxOf(decoded.width, decoded.height) <= 256)
            assertFalse(decoded.hasAlpha())
        }

    @Test
    fun thumbGeneration_maxPx4096_clampedTo384() =
        runTest {
            val outcome =
                responder().respond(
                    thumbRequest {
                        id = "7"
                        maxPx = 4096
                    },
                )

            val decoded = decode((outcome as ThumbOutcome.Thumb).result.pngBytes.toByteArray())
            assertEquals(listOf(384), requestedSizes)
            assertEquals(384, maxOf(decoded.width, decoded.height))
        }

    @Test
    fun thumbGeneration_maxPx8_clampedTo32() =
        runTest {
            responder().respond(
                thumbRequest {
                    id = "7"
                    maxPx = 8
                },
            )

            assertEquals(listOf(32), requestedSizes)
        }

    @Test
    fun thumbGeneration_idOutsideGrant_accessDeniedErrorAndNextRequestServed() =
        runTest {
            val responder =
                responder { id, _ ->
                    if (id == 1L) throw SecurityException("outside grant")
                    Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
                }

            val denied =
                responder.respond(
                    thumbRequest {
                        id = "1"
                        maxPx = 64
                    },
                )
            val served =
                responder.respond(
                    thumbRequest {
                        id = "2"
                        maxPx = 64
                    },
                )

            val error = (denied as ThumbOutcome.Failure).error
            assertEquals(PhotoErrorKind.PHOTO_ERROR_KIND_THUMB, error.kind)
            assertEquals("1", error.ref)
            assertEquals(PhotoErrorReason.PHOTO_ERROR_REASON_ACCESS_DENIED, error.reason)
            assertTrue(served is ThumbOutcome.Thumb)
        }

    @Test
    fun thumbGeneration_missingOrMalformedId_notFoundError() =
        runTest {
            val responder = responder { _, _ -> throw FileNotFoundException() }

            val missing =
                responder.respond(
                    thumbRequest {
                        id = "9"
                        maxPx = 64
                    },
                )
            val malformed =
                responder.respond(
                    thumbRequest {
                        id = "not-a-number"
                        maxPx = 64
                    },
                )

            listOf(missing, malformed).forEach {
                assertEquals(PhotoErrorReason.PHOTO_ERROR_REASON_NOT_FOUND, (it as ThumbOutcome.Failure).error.reason)
            }
        }

    @Test
    fun thumbGeneration_ninthOutstandingRequest_busyErrorNoLoad() =
        runTest {
            val loaderDispatcher = StandardTestDispatcher(testScheduler)
            val responder = ThumbnailResponder(fakeLoader(), loaderDispatcher)
            repeat(ThumbnailResponder.MAX_OUTSTANDING) { index ->
                launch(UnconfinedTestDispatcher(testScheduler)) {
                    responder.respond(
                        thumbRequest {
                            id = "$index"
                            maxPx = 64
                        },
                    )
                }
            }

            val ninth =
                responder.respond(
                    thumbRequest {
                        id = "99"
                        maxPx = 64
                    },
                )

            val error = (ninth as ThumbOutcome.Failure).error
            assertEquals(PhotoErrorReason.PHOTO_ERROR_REASON_BUSY, error.reason)
            assertTrue(requestedSizes.isEmpty())
            loaderDispatcher.scheduler.advanceUntilIdle()
            assertEquals(ThumbnailResponder.MAX_OUTSTANDING, requestedSizes.size)
        }
}
