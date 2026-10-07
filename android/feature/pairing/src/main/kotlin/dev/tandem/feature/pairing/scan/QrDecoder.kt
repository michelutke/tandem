package dev.tandem.feature.pairing.scan

import android.graphics.Bitmap
import androidx.camera.core.ImageProxy
import zxingcpp.BarcodeReader

/**
 * The decoder chosen by the E14-23 spike (docs/spikes/qr-decoder.md): zxing-cpp, restricted to
 * `QR_CODE` so other barcode formats are never even returned. Wraps both overloads this feature
 * needs: [decode] over a live CameraX frame (the real scanner path) and [decodeBitmap] over an
 * already-decoded bitmap (the `instrumented:` fixture test, `docs/testing/manual-gates.md`'s
 * `qrScanner_realCameraMacDisplay_decodesWithin3s` gate covers the live-camera timing).
 */
class QrDecoder {
    private val reader = BarcodeReader(BarcodeReader.Options(formats = setOf(BarcodeReader.Format.QR_CODE), tryHarder = true))

    /** Closes [image] (CameraX requires every analyzed frame to be closed exactly once). */
    fun decode(image: ImageProxy): String? = image.use { reader.read(it) }.firstOrNull()?.text

    fun decodeBitmap(bitmap: Bitmap): String? = reader.read(bitmap).firstOrNull()?.text
}
