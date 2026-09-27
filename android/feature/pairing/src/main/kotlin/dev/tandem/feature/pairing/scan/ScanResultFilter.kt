package dev.tandem.feature.pairing.scan

private const val TANDEM_SCHEME_PREFIX = "tandem://"

/**
 * Pure decode-result gate (E14-10): a CameraX analyzer callback can fire many times per second on
 * the same physical QR code, and other barcode formats/content must never reach
 * `QrPayloadParser` (E14-03). [apply] accepts only a `QR_CODE` result whose raw value starts with
 * the `tandem://` scheme, and de-duplicates immediate repeats so a code held in view across
 * several consecutive frames is only ever accepted once. A different value (a fresh scan) resets
 * the de-dupe so a subsequent, different tandem:// code is still accepted.
 */
class ScanResultFilter {
    private var lastAccepted: String? = null

    fun apply(result: ScanResult): ScanOutcome {
        val isNewTandemQr =
            result.format == ScanFormat.QR_CODE &&
                result.rawValue.startsWith(TANDEM_SCHEME_PREFIX) &&
                result.rawValue != lastAccepted
        if (!isNewTandemQr) return ScanOutcome.Ignore

        lastAccepted = result.rawValue
        return ScanOutcome.Accept(result.rawValue)
    }
}
