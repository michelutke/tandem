package dev.tandem.core.pairing.qr

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.SpkiFingerprint

/**
 * A [PinSource] that returns only the Mac fingerprint from the scanned QR pairing invite.
 * Per SPEC.md §1, the phone side has no carve-out that adds to this set; the only expected
 * fingerprint during a pairing attempt is the one from the QR payload. This PinSource is registered
 * for the duration of the pairing attempt and unregistered when the attempt ends (E14-04).
 */
class QrPairingPinSource(
    private val invite: PairingInvite,
) : PinSource {
    override fun expectedFingerprints(): List<SpkiFingerprint> {
        // Return only the QR invite's fingerprint, never any trust store pins.
        return listOf(SpkiFingerprint(invite.fingerprint))
    }
}
