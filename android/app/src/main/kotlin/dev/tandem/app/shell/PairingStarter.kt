package dev.tandem.app.shell

import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.core.pairing.qr.PairingInvite

/**
 * Hands a scanned [PairingInvite] to the real pairing flow (E20-25). Trust is committed only by
 * that flow (`PairingStateMachine`: pinned dial to the QR fingerprint, proof, mutual "Codes match"
 * confirmation, then `TrustCommitter`), never by the app shell: the shell neither pins a
 * fingerprint nor treats an address as trusted (invariants 3, 5). The shell only observes the
 * trust store, so it shows Home once the flow has committed a peer. The production flow
 * (connector, committer, confirmation UI) is E20-26; until then [NoOpPairingStarter] is bound.
 */
fun interface PairingStarter {
    fun start(invite: PairingInvite)
}

/** Placeholder until E20-26: starts nothing, so no trust is ever created. */
object NoOpPairingStarter : PairingStarter {
    override fun start(invite: PairingInvite) = Unit
}

/**
 * Saves [invite]'s addresses as reconnect candidates (a hint only, never trust) and starts the
 * pairing flow through [pairingStarter].
 */
internal fun onScanAccepted(
    invite: PairingInvite,
    addressStore: PairingAddressStore,
    pairingStarter: PairingStarter,
) {
    addressStore.save(invite.addresses, invite.port)
    pairingStarter.start(invite)
}
