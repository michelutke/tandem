import Foundation

/// Decides whether a candidate's `PairRequest.proof` is valid for this attempt's secret and
/// channel-binding challenge (`docs/protocol/SPEC.md` § Pairing, "Proof computation"). The actual
/// HMAC/transcript computation -- including `macSpkiDer`/`phoneSpkiDer`, which this window never
/// sees -- is E14-07's concern; this seam lets ``PairingWindow`` enforce the attempt budget and
/// window-state rules against a fake in tests, without depending on that crypto (and without this
/// package computing HMAC-SHA256 itself, which only TandemCrypto may do).
public protocol PairRequestVerifier: Sendable {
    func verify(proof: Data, secret: Data, challenge: Data) -> Bool
}
