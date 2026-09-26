package dev.tandem.feature.pairing.scan

/** Outcome of [ScanResultFilter.apply]. */
sealed interface ScanOutcome {
    data class Accept(
        val rawValue: String,
    ) : ScanOutcome

    data object Ignore : ScanOutcome
}
