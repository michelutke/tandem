package dev.tandem.feature.pairing.scan

/** A decoded barcode frame, decoupled from any specific decoder library (E14-23). */
enum class ScanFormat {
    QR_CODE,
    OTHER,
}

data class ScanResult(
    val format: ScanFormat,
    val rawValue: String,
)
