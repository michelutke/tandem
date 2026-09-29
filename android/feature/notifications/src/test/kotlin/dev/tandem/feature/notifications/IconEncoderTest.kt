package dev.tandem.feature.notifications

import android.graphics.Color
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.ColorDrawable
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * `IconEncoder` test (E30-05; `docs/planning/backlog/phase-3.yaml` E30-05's `tdd:` list). Uses a
 * real `AdaptiveIconDrawable` (API 26+, the shape most installed apps' launcher icons actually use)
 * rather than a plain `BitmapDrawable`, since compositing its background+foreground layers into a
 * flat PNG is the interesting case `PackageManager.getApplicationIcon` hands this encoder in
 * practice.
 */
@RunWith(AndroidJUnit4::class)
class IconEncoderTest {
    @Test
    fun iconEncoder_adaptiveIconDrawable_bytesStartWithPngSignature() {
        val drawable = AdaptiveIconDrawable(ColorDrawable(Color.BLUE), ColorDrawable(Color.WHITE))

        val bytes = IconEncoder.encode(drawable)

        assertArrayEquals(PNG_SIGNATURE, bytes.copyOfRange(0, PNG_SIGNATURE.size))
    }

    private companion object {
        val PNG_SIGNATURE =
            byteArrayOf(
                0x89.toByte(),
                0x50,
                0x4E,
                0x47,
                0x0D,
                0x0A,
                0x1A,
                0x0A,
            )
    }
}
