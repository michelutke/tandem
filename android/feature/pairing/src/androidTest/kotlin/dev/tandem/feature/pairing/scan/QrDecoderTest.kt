package dev.tandem.feature.pairing.scan

import android.graphics.BitmapFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

// E14-10 tdd: instrumented: qrDecoder_fixtureTandemQrBitmap_returnsFixtureString
//
// Fixture reused from the E14-23 spike (spikes/e14-23-qr-decoder/fixtures/typical.png,
// docs/spikes/qr-decoder.md): a committed tandem://pair QR, decoded through the same zxing-cpp
// BarcodeReader.Options this module's live scanner path (ZxingQrAnalyzer/QrDecoder) uses. Not a
// live camera feed (that gate is `manual: qrScanner_realCameraMacDisplay_decodesWithin3s`,
// docs/testing/manual-gates.md).
@RunWith(AndroidJUnit4::class)
class QrDecoderTest {
    // Packaged into the instrumentation (test) APK, not the app-under-test APK.
    private val instrumentationContext = InstrumentationRegistry.getInstrumentation().context

    @Test
    fun qrDecoder_fixtureTandemQrBitmap_returnsFixtureString() {
        val expected =
            instrumentationContext.assets
                .open("typical.txt")
                .bufferedReader()
                .use { it.readText() }
        val bitmap = BitmapFactory.decodeStream(instrumentationContext.assets.open("typical.png"))

        val decoded = QrDecoder().decodeBitmap(bitmap)

        assertEquals(expected, decoded)
    }
}
