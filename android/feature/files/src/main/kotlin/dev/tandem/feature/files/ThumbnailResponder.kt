package dev.tandem.feature.files

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import androidx.core.graphics.createBitmap
import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.PhotoError
import dev.tandem.protocol.v1.PhotoErrorKind
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.ThumbRequest
import dev.tandem.protocol.v1.ThumbResult
import dev.tandem.protocol.v1.photoError
import dev.tandem.protocol.v1.thumbResult
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.util.concurrent.atomic.AtomicInteger

sealed interface ThumbOutcome {
    data class Thumb(
        val result: ThumbResult,
    ) : ThumbOutcome

    data class Failure(
        val error: PhotoError,
    ) : ThumbOutcome
}

/**
 * Answers a `ThumbRequest` with an RGB PNG whose longest edge is at most the clamped `max_px`
 * (32..384). A 9th outstanding request is rejected BUSY before any thumbnail is loaded.
 */
class ThumbnailResponder(
    private val loader: ThumbnailLoader,
    private val dispatcher: CoroutineDispatcher,
) {
    private val outstanding = AtomicInteger(0)

    suspend fun respond(request: ThumbRequest): ThumbOutcome {
        if (outstanding.incrementAndGet() > MAX_OUTSTANDING) {
            outstanding.decrementAndGet()
            return failure(request.id, PhotoErrorReason.PHOTO_ERROR_REASON_BUSY)
        }
        try {
            return withContext(dispatcher) { generate(request) }
        } finally {
            outstanding.decrementAndGet()
        }
    }

    private fun generate(request: ThumbRequest): ThumbOutcome {
        val id = request.id.toLongOrNull()
        val maxPx = clampMaxPx(request.maxPx)
        val source =
            try {
                id?.let { loader.load(it, maxPx) }
            } catch (_: FileNotFoundException) {
                null
            } catch (_: SecurityException) {
                return failure(request.id, PhotoErrorReason.PHOTO_ERROR_REASON_ACCESS_DENIED)
            }
        return if (source == null) {
            failure(request.id, PhotoErrorReason.PHOTO_ERROR_REASON_NOT_FOUND)
        } else {
            ThumbOutcome.Thumb(
                thumbResult {
                    this.id = request.id
                    pngBytes = ByteString.copyFrom(encodeRgbPng(source, maxPx))
                },
            )
        }
    }

    private fun clampMaxPx(maxPx: Int): Int = maxPx.coerceIn(MIN_PX, MAX_PX)

    private fun encodeRgbPng(
        source: Bitmap,
        maxPx: Int,
    ): ByteArray {
        val scale = minOf(1f, maxPx.toFloat() / maxOf(source.width, source.height))
        val width = maxOf(1, (source.width * scale).toInt())
        val height = maxOf(1, (source.height * scale).toInt())
        val target = createBitmap(width, height)
        Canvas(target).apply {
            drawColor(Color.WHITE)
            drawBitmap(source, null, Rect(0, 0, width, height), null)
        }
        target.setHasAlpha(false)
        return ByteArrayOutputStream().use { out ->
            target.compress(Bitmap.CompressFormat.PNG, PNG_QUALITY, out)
            out.toByteArray()
        }
    }

    private fun failure(
        id: String,
        reason: PhotoErrorReason,
    ): ThumbOutcome.Failure =
        ThumbOutcome.Failure(
            photoError {
                kind = PhotoErrorKind.PHOTO_ERROR_KIND_THUMB
                ref = id.take(MAX_REF_LENGTH)
                this.reason = reason
            },
        )

    companion object {
        const val MIN_PX = 32
        const val MAX_PX = 384
        const val MAX_OUTSTANDING = 8
        private const val MAX_REF_LENGTH = 64
        private const val PNG_QUALITY = 100
    }
}
