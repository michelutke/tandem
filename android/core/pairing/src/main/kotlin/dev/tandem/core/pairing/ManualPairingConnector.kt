package dev.tandem.core.pairing

/**
 * Session-factory seam [ManualPairingStateMachine] dials through (E73-03, ADR-008): completes the
 * mTLS handshake with a Mac whose SPKI is not yet pinned -- manual pairing has no QR fingerprint,
 * so the SAS comparison is the only authenticator -- and exchanges `VersionHello`. The returned
 * [PairingConnection] carries the SPKIs actually observed on the handshake. Nothing but the
 * pairing messages may ever be sent on it. Tests supply a fake wrapping a `FakeTandemSession`.
 */
fun interface ManualPairingConnector {
    suspend fun connect(
        address: String,
        port: Int,
    ): PairingConnection
}
