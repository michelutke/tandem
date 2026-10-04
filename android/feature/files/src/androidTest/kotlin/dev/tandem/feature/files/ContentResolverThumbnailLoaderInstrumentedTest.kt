package dev.tandem.feature.files

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.thumbRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

// E41-04 tdd: instrumented: thumbnailLoader_seeded4000x3000Jpeg_pngAtMost384pxAnd450KiB
// Runs on the api35 managed device (E00-21) with media access granted by the test harness.
@RunWith(AndroidJUnit4::class)
class ContentResolverThumbnailLoaderInstrumentedTest {
    private val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
    private var seededId = 0L

    @Before
    fun seedImage() {
        val values =
            ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "tandem-e41-04.jpg")
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.WIDTH, SEED_WIDTH)
                put(MediaStore.Images.Media.HEIGHT, SEED_HEIGHT)
            }
        val uri = requireNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
        resolver.openOutputStream(uri)!!.use { out ->
            val bitmap = Bitmap.createBitmap(SEED_WIDTH, SEED_HEIGHT, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.MAGENTA)
            bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
        }
        seededId = uri.lastPathSegment!!.toLong()
    }

    @After
    fun removeSeededImage() {
        resolver.delete(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "_id = ?", arrayOf(seededId.toString()))
    }

    @Test
    fun thumbnailLoader_seeded4000x3000Jpeg_pngAtMost384pxAnd450KiB() =
        runBlocking {
            val responder = ThumbnailResponder(ContentResolverThumbnailLoader(resolver), Dispatchers.IO)

            val outcome =
                responder.respond(
                    thumbRequest {
                        id = seededId.toString()
                        maxPx = 4096
                    },
                )

            val bytes = (outcome as ThumbOutcome.Thumb).result.pngBytes.toByteArray()
            val decoded = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
            assertTrue(maxOf(decoded.width, decoded.height) <= 384)
            assertTrue(bytes.size <= MAX_PNG_BYTES)
        }

    private companion object {
        const val SEED_WIDTH = 4000
        const val SEED_HEIGHT = 3000
        const val JPEG_QUALITY = 90
        const val MAX_PNG_BYTES = 450 * 1024
    }
}
