package dev.tandem.core.pairing

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.transport.TandemSession

/**
 * Feature-local session-factory seam [PairingStateMachine] dials through (E14-05; SPEC.md §2
 * "Dialing the QR addresses (phone side)"): the sole place a real implementation opens a socket,
 * completes the mTLS handshake pinned to [pinSource], and exchanges `VersionHello`. Tests supply a
 * fake returning a [PairingConnection] wrapping a `FakeTandemSession` (E12-11 testFixtures), so no
 * [PairingStateMachine] test ever opens a socket.
 */
fun interface PairingConnector {
    /**
     * Dials [address]:[port], pinned to [pinSource] (E14-04: the QR fingerprint only, never the
     * trust store). Suspends until the connection is ready to receive `PairChallenge` (TLS
     * complete, both `VersionHello`s exchanged); the caller applies its own 3 s-per-address timeout
     * (D-68).
     */
    suspend fun connect(
        address: String,
        port: Int,
        pinSource: PinSource,
    ): PairingConnection
}

/**
 * A [session] ready for the pairing frame exchange (SPEC.md §2, Frame order), plus the two SPKIs
 * the proof and confirmation-code formulas need (SPEC.md §2, Proof computation) — [macSpkiDer] is
 * the Mac leaf certificate's SPKI actually observed on this handshake (never derived from the QR
 * `fp` hash, which cannot be reversed to it), [phoneSpkiDer] this phone's own client-certificate
 * SPKI. Deliberately a plain class, not a `data class`: `ByteArray` fields must never be compared
 * with the generated structural `equals`/`hashCode` (mirrors [dev.tandem.core.pairing.qr.PairingInvite]).
 */
class PairingConnection(
    val session: TandemSession,
    val macSpkiDer: ByteArray,
    val phoneSpkiDer: ByteArray,
)
