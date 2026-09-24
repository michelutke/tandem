import Foundation
import Network
import Security

/// E03-04 experiment 2 (API 29 in-band-challenge fallback): a single-slot holder for the peer
/// public key captured by the TLS verify_block (TLSSetup.swift), read by the connection's ready
/// handler right after the handshake completes.
///
/// Spike simplification, not a production pattern: this only works because the driving harness
/// (`scripts/run-e2e.sh`) makes exactly one connection at a time. `sec_protocol_options_set_verify_block`
/// has no connection handle to key a per-connection map by, and E03-01 §8 already established that
/// verify_block always completes strictly before that same connection's `.ready` fires -- so for a
/// single in-flight connection, "most recently verified key" and "this connection's peer key" are
/// the same thing. A production implementation binding real pairing/rotation challenges to a
/// specific connection must carry the key on the connection object itself, not a shared slot.
final class PendingPeerKeyStore {
    static let shared = PendingPeerKeyStore()
    private let lock = NSLock()
    private var key: SecKey?

    func set(_ key: SecKey) {
        lock.lock(); self.key = key; lock.unlock()
    }

    func takeAndClear() -> SecKey? {
        lock.lock(); defer { lock.unlock() }
        let key = self.key
        self.key = nil
        return key
    }
}

let challengeLength = 32

func randomChallenge() -> Data {
    var bytes = [UInt8](repeating: 0, count: challengeLength)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
    return Data(bytes)
}

/// Verifies a DER-encoded ECDSA-over-SHA256 signature (Java's `Signature.getInstance("SHA256withECDSA")`
/// output format) over `challenge`, produced by the peer's pinned private key. This is the "proof
/// covers the challenge" half of the in-band fallback: the signature could only have been produced
/// by the holder of the already-pinned, mutually-authenticated identity key, and it covers bytes
/// that only exist inside this one live TLS session (never transmitted or reused elsewhere).
func verifyChallengeSignature(challenge: Data, signatureDER: Data, publicKey: SecKey) -> Bool {
    var error: Unmanaged<CFError>?
    let ok = SecKeyVerifySignature(
        publicKey,
        .ecdsaSignatureMessageX962SHA256,
        challenge as CFData,
        signatureDER as CFData,
        &error
    )
    if let error {
        print("LOG[listener] challenge verify error: \(error.takeRetainedValue())")
    }
    return ok
}

/// Client-role counterpart of `SpikeListener.runChallenge`, used only by `client-challenge` (see
/// main.swift) as a Swift-only sanity double for the Android path.
func runChallengeClient(host: String, port: UInt16, options: NWProtocolTLS.Options, privateKey: SecKey, timeout: TimeInterval) -> Int32 {
    let params = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 3
    var finished = false
    func finish(_ code: Int32) {
        guard !finished else { return }
        finished = true
        exitCode = code
        semaphore.signal()
    }

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("EVENT type=ready role=client")
            connection.receive(minimumIncompleteLength: challengeLength, maximumLength: challengeLength) { data, _, _, _ in
                guard let challenge = data, challenge.count == challengeLength else {
                    print("EVENT type=challenge-error role=client error=\"short challenge read\"")
                    finish(1)
                    return
                }
                var error: Unmanaged<CFError>?
                guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, challenge as CFData, &error) as Data? else {
                    print("EVENT type=challenge-error role=client error=\"sign failed: \(String(describing: error))\"")
                    finish(1)
                    return
                }
                var payload = Data([UInt8(signature.count)])
                payload.append(signature)
                connection.send(content: payload, completion: .contentProcessed { sendError in
                    if let sendError {
                        print("EVENT type=challenge-error role=client error=\"send failed: \(sendError)\"")
                        finish(1)
                        return
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { ackData, _, _, _ in
                        let ok = ackData?.first == 0x01
                        print("EVENT type=challenge-result role=client ack_ok=\(ok) challenge_sha256=\(sha256Hex(challenge))")
                        finish(ok ? 0 : 1)
                    }
                })
            }
        case .failed(let error):
            print("EVENT type=failed role=client error=\"\(error)\"")
            finish(1)
        case .waiting(let error):
            print("EVENT type=waiting role=client error=\"\(error)\"")
        default:
            break
        }
    }
    connection.start(queue: DispatchQueue(label: "challenge-client"))

    if semaphore.wait(timeout: .now() + timeout) == .timedOut {
        print("EVENT type=timeout role=client after_s=\(timeout)")
        connection.cancel()
        return 2
    }
    connection.cancel()
    return exitCode
}
