package dev.tandem.core.pairing

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PairingProof
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.protocol.v1.deviceInfo
import dev.tandem.protocol.v1.pairRequest

/**
 * Builder for constructing a PairRequest with a computed pairing proof (E14-06).
 * Takes the pairing invite, peer SPKI DER, local phone SPKI DER, and the received
 * PairChallenge value, then constructs a complete PairRequest with proof attached.
 */
object PairRequestBuilder {
    fun build(
        invite: PairingInvite,
        macSpkiDer: ByteArray,
        phoneSpkiDer: ByteArray,
        challenge: ByteArray,
    ) = pairRequest {
        proof =
            ByteString.copyFrom(
                PairingProof.compute(
                    invite.secret,
                    macSpkiDer,
                    phoneSpkiDer,
                    challenge,
                ),
            )
        deviceInfo =
            deviceInfo {
                displayName = ""
                model = ""
                appVersion = ""
            }
    }
}
