package com.tandem.spike.qrdecoder

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import zxingcpp.BarcodeReader

private const val TAG = "E1423Spike"
private const val TIMED_RUNS = 20

/**
 * E14-23 spike: decodes committed tandem://pair QR fixture PNGs (not a live camera feed) through
 * zxing-cpp's native decoder. Timing and correctness only; network egress is observed by
 * scripts/run-spike.sh around this test's process lifetime (dumpsys netstats + a tcpdump
 * capture), not asserted here.
 */
@RunWith(AndroidJUnit4::class)
class ZxingCppDecoderSpikeTest {

    // Fixture PNGs/txt live under src/androidTest/assets, which are packaged into the
    // instrumentation (test) APK, not the app-under-test APK — so assets must be read from the
    // instrumentation context, not targetContext.
    private val context = InstrumentationRegistry.getInstrumentation().context
    private val reader = BarcodeReader(
        BarcodeReader.Options(formats = setOf(BarcodeReader.Format.QR_CODE))
    )

    @Test
    fun decode_typicalFixture_matchesExpectedPayload() {
        val expected = readAsset("typical.txt")
        val text = decodeOnce("typical.png")
        assertEquals(expected, text)
    }

    @Test
    fun decode_maxFixture_matchesExpectedPayload() {
        val expected = readAsset("max.txt")
        val text = decodeOnce("max.png")
        assertEquals(expected, text)
    }

    @Test
    fun decode_typicalFixture_timed20Runs_logsMedianAndP95() {
        val bitmap = BitmapFactory.decodeStream(context.assets.open("typical.png"))
        // Warm-up run: excluded from timing, matches a decoder already initialized once before
        // the real pairing scan (CameraX preview frames precede the first successful decode).
        decodeBitmap(bitmap)

        val latenciesMs = mutableListOf<Long>()
        repeat(TIMED_RUNS) { i ->
            val start = System.nanoTime()
            val text = decodeBitmap(bitmap)
            val elapsedMs = (System.nanoTime() - start) / 1_000_000
            assertEquals(readAsset("typical.txt"), text)
            latenciesMs += elapsedMs
            Log.i(TAG, "decoder=zxing-cpp run=$i latencyMs=$elapsedMs")
        }

        val sorted = latenciesMs.sorted()
        val p50 = sorted[TIMED_RUNS / 2]
        val p95 = sorted[(TIMED_RUNS * 95 / 100).coerceAtMost(TIMED_RUNS - 1)]
        Log.i(TAG, "decoder=zxing-cpp summary p50Ms=$p50 p95Ms=$p95 all=$sorted")
    }

    private fun decodeOnce(assetName: String): String? {
        val bitmap = BitmapFactory.decodeStream(context.assets.open(assetName))
        return decodeBitmap(bitmap)
    }

    private fun decodeBitmap(bitmap: Bitmap): String? =
        reader.read(bitmap).firstOrNull { it.format == BarcodeReader.Format.QR_CODE }?.text

    private fun readAsset(name: String): String =
        context.assets.open(name).bufferedReader().use { it.readText() }
}
