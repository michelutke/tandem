package dev.tandem.core.crypto

/**
 * The set of SPKI fingerprints this side currently accepts as the peer's identity (SPEC.md §1,
 * "Verify-callback algorithm", step 4: "every fingerprint this side's trust store holds").
 * [PinningTrustManager] is written against this small interface rather than against the trust
 * store (E13-02) or the pairing-scan pin (E14-04) directly, since both are built concurrently
 * with this issue: a higher layer composes them — ordinarily the trust store's paired-Mac record,
 * or, while a pairing scan is in progress, the QR-scanned fingerprint instead. SPEC.md §1 notes
 * the phone has no carve-out that adds to this set: unlike the Mac's pairing-window relaxation,
 * the phone only ever has a single expected fingerprint (or set of fingerprints during rotation,
 * E70-01) substituted in, never widened.
 */
fun interface PinSource {
    fun expectedFingerprints(): List<SpkiFingerprint>
}
