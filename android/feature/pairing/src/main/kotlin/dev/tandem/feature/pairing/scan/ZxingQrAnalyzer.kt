package dev.tandem.feature.pairing.scan

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy

/**
 * The CameraX [ImageAnalysis.Analyzer] for the live scanner path: decodes each frame through
 * [QrDecoder] and reports a hit as a [ScanResult]. Kept behind the [ImageAnalysis.Analyzer]
 * interface (and only ever constructed inside [CameraXFrameSource]) so nothing else in this module
 * needs a real camera to run — Compose `ui:` tests substitute [CameraXFrameSource]'s whole slot
 * with a fake frame source instead (E00-20).
 */
internal class ZxingQrAnalyzer(
    private val onResult: (ScanResult) -> Unit,
    private val decoder: QrDecoder = QrDecoder(),
) : ImageAnalysis.Analyzer {
    override fun analyze(image: ImageProxy) {
        val rawValue = decoder.decode(image)
        if (rawValue != null) {
            onResult(ScanResult(format = ScanFormat.QR_CODE, rawValue = rawValue))
        }
    }
}
