package dev.tandem.feature.pairing.scan

/** UI states for [ScannerScreen] (E14-10; ui-spec.md §7.2 "Scan"). */
sealed interface ScannerUiState {
    /** Camera permission not yet granted; the camera never opens (UC-02 exception: no skip). */
    data object CameraPermissionRequired : ScannerUiState

    /** Camera preview is live, feeding decoded frames through [ScanResultFilter]. */
    data object Scanning : ScannerUiState
}
