import Foundation
import Network
import Security
import CryptoKit
import Dispatch

enum TicketMode: String { case enabled, disabled }
enum AlpnMode { case require(String), none }

struct PinPolicy {
    let expectedFingerprint: Data
    /// D-19 / F-2.1 pairing-window carve-out: the Mac MAY accept an unknown client key while a
    /// pairing window is open. The spike only *simulates* this switch (a flag flipped from the
    /// CLI); it does not implement the real pairing state machine (that is E01-02 scope).
    let acceptAnyClient: Bool
}

/// Builds `NWProtocolTLS.Options` shared by both the listener and the client role. Logging goes
/// through `log` so callers can prefix listener/client output distinctly when both run in the
/// same terminal.
func makeTLSOptions(
    localIdentity: SecIdentity,
    peerAuthenticationRequired: Bool,
    alpn: AlpnMode,
    pin: PinPolicy?,
    ticketMode: TicketMode,
    resumptionEnabled: Bool,
    maxVersionOverride: tls_protocol_version_t? = nil,
    onPeerVerified: ((SecKey) -> Void)? = nil,
    log: @escaping (String) -> Void
) -> NWProtocolTLS.Options {
    let options = NWProtocolTLS.Options()
    let sec = options.securityProtocolOptions

    sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
    sec_protocol_options_set_max_tls_protocol_version(sec, maxVersionOverride ?? .TLSv13)

    guard let secIdentityRef = sec_identity_create(localIdentity) else {
        fatalError("sec_identity_create failed for local identity")
    }
    sec_protocol_options_set_local_identity(sec, secIdentityRef)

    switch alpn {
    case .require(let proto):
        sec_protocol_options_add_tls_application_protocol(sec, proto)
    case .none:
        break
    }

    sec_protocol_options_set_tls_tickets_enabled(sec, ticketMode == .enabled)
    sec_protocol_options_set_tls_resumption_enabled(sec, resumptionEnabled)

    if peerAuthenticationRequired {
        sec_protocol_options_set_peer_authentication_required(sec, true)
    }

    if let pin = pin {
        let queue = DispatchQueue(label: "verify-block")
        sec_protocol_options_set_verify_block(sec, { metadata, trustRef, complete in
            let verifyStart = DispatchTime.now()
            let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
                log("verify_block: no leaf certificate presented -> reject")
                complete(false)
                return
            }
            do {
                let digest = try spkiFingerprint(for: leaf)
                if pin.acceptAnyClient {
                    log("verify_block: pairing-window simulation, accepting unpinned key \(hex(digest).prefix(16))...")
                    complete(true)
                    return
                }
                let match = constantTimeEqual(digest, pin.expectedFingerprint)
                let elapsedUs = Double(DispatchTime.now().uptimeNanoseconds - verifyStart.uptimeNanoseconds) / 1000.0
                log("verify_block: peer_spki=\(hex(digest).prefix(16))... match=\(match) elapsed_us=\(elapsedUs)")
                if match, let peerKey = SecCertificateCopyKey(leaf) {
                    onPeerVerified?(peerKey)
                }
                complete(match)
            } catch {
                log("verify_block: fingerprint error \(error) -> reject")
                complete(false)
            }
        }, queue)
    }

    return options
}

/// RFC 9266 channel binding: `TLS-Exporter("EXPORTER-Channel-Binding", context = empty, 32)`.
/// Never returns/logs the raw secret -- callers should only log the SHA-256 of it.
func channelBindingExporter(from metadata: sec_protocol_metadata_t) -> Data? {
    let label = "EXPORTER-Channel-Binding"
    guard let secret = label.withCString({ cLabel in
        sec_protocol_metadata_create_secret(metadata, label.utf8.count, cLabel, 32)
    }) else { return nil }
    let dispatchData = secret as DispatchData
    let result = Data(dispatchData)
    return result.count == 32 ? result : nil
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
