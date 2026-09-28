package dev.tandem.app.onboarding

/**
 * Documents SPEC.md/UC-02's pairing gate (E20-14 acceptance criteria): pairing is never blocked
 * on any optional onboarding permission. [isPairingAllowed] takes no permission state at all and
 * always returns true -- notification-listener access, POST_NOTIFICATIONS and the
 * battery-optimization exemption never factor into it, granted, skipped or denied. Scan Mac QR
 * (and the pairing it starts) only ever depends on the CAMERA permission
 * [dev.tandem.feature.pairing.scan.ScannerScreen] itself already gates (E14-10).
 */
object PairingPreconditions {
    // A `const val` would read the same but lose the call-site shape ("is pairing allowed?")
    // this invariant is documented against; kept as a function deliberately.
    @Suppress("FunctionOnlyReturningConstant")
    fun isPairingAllowed(): Boolean = true
}
