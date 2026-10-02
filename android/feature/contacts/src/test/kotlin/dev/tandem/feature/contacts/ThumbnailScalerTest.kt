package dev.tandem.feature.contacts

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayOutputStream
import java.util.Random

/** ThumbnailScaler tests (E51-09) under Robolectric native graphics mode (E00-20). */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ThumbnailScalerTest {
    private val scaler = ThumbnailScaler()

    @Test
    fun thumbnailScaler_largePhoto512px_outputLongestEdgeAtMost96px() {
        val output = requireNotNull(scaler.scale(photoBytes(512, 384)))

        val decoded = requireNotNull(BitmapFactory.decodeByteArray(output, 0, output.size))
        assertTrue(maxOf(decoded.width, decoded.height) <= ThumbnailScaler.MAX_EDGE_PX)
        assertTrue(decoded.width > 0 && decoded.height > 0)
    }

    @Test
    fun thumbnailScaler_anyPhoto_outputAtMost32768Bytes() {
        listOf(photoBytes(512, 384, noisy = true), photoBytes(96, 96, noisy = true), photoBytes(40, 30)).forEach {
            val output = scaler.scale(it)
            assertNotNull(output)
            assertTrue(requireNotNull(output).size <= ThumbnailScaler.MAX_BYTES)
        }
    }

    @Test
    fun thumbnailScaler_corruptImageBytes_returnsNoThumbnail() {
        assertNull(scaler.scale(ByteArray(64) { it.toByte() }))
        assertNull(scaler.scale(ByteArray(0)))
    }

    private fun photoBytes(
        width: Int,
        height: Int,
        noisy: Boolean = false,
    ): ByteArray {
        val random = Random(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        for (x in 0 until width) {
            for (y in 0 until height) {
                bitmap.setPixel(
                    x,
                    y,
                    if (noisy) {
                        Color.rgb(random.nextInt(256), random.nextInt(256), random.nextInt(256))
                    } else {
                        Color.rgb(x % 256, y % 256, 90)
                    },
                )
            }
        }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }.toByteArray()
    }
}
