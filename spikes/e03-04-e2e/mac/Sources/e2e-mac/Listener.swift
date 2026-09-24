import Foundation
import Network
import Security

final class SpikeListener {
    private let listener: NWListener
    private let handshakeDeadline: TimeInterval
    private let exitAfter: Int?
    private let challengeMode: Bool
    private var terminalCount = 0
    private let lock = NSLock()
    private var openConnections: [ObjectIdentifier: NWConnection] = [:]

    init(port: UInt16, options: NWProtocolTLS.Options, handshakeDeadline: TimeInterval, exitAfter: Int?, challengeMode: Bool = false, bindHost: String = "127.0.0.1") throws {
        let params = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(bindHost), port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        self.handshakeDeadline = handshakeDeadline
        self.exitAfter = exitAfter
        self.challengeMode = challengeMode
        self.listener = try NWListener(using: params)
    }

    func start() {
        listener.stateUpdateHandler = { state in
            print("EVENT type=listener-state state=\(state)")
            if case .failed(let error) = state {
                print("EVENT type=listener-failed error=\"\(error)\"")
                exit(1)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        let start = DispatchTime.now()
        let id = ObjectIdentifier(connection)
        lock.lock(); openConnections[id] = connection; lock.unlock()

        // Acceptance item (d): can the listener read the remote endpoint before the TLS
        // handshake completes? `connection.endpoint` is available immediately, before `start()`.
        print("EVENT type=pre-handshake-endpoint remote=\(connection.endpoint)")

        var reachedReady = false
        let deadlineWorkItem = DispatchWorkItem { [weak self] in
            guard !reachedReady else { return }
            print("EVENT type=handshake-deadline-cancel remote=\(connection.endpoint) deadline_s=\(self?.handshakeDeadline ?? -1)")
            connection.cancel()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeDeadline, execute: deadlineWorkItem)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            switch state {
            case .ready:
                reachedReady = true
                deadlineWorkItem.cancel()
                self.describeReady(connection: connection, elapsedMs: elapsedMs)
                if self.challengeMode {
                    self.runChallenge(connection)
                } else {
                    self.receiveLoop(connection)
                }
            case .failed(let error):
                deadlineWorkItem.cancel()
                print("EVENT type=failed role=server remote=\(connection.endpoint) error=\"\(error)\" elapsed_ms=\(elapsedMs)")
                self.finish(connection)
            case .cancelled:
                print("EVENT type=cancelled role=server remote=\(connection.endpoint) elapsed_ms=\(elapsedMs)")
                self.finish(connection)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func describeReady(connection: NWConnection, elapsedMs: Double) {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            print("EVENT type=ready role=server remote=\(connection.endpoint) note=\"no TLS metadata\" elapsed_ms=\(elapsedMs)")
            return
        }
        let secMetadata = metadata.securityProtocolMetadata
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(secMetadata)
        var alpn = "none"
        if let negotiated = sec_protocol_metadata_get_negotiated_protocol(secMetadata) {
            alpn = String(cString: negotiated)
        }
        var exporterSha = "unavailable"
        if let exporter = channelBindingExporter(from: secMetadata) {
            exporterSha = sha256Hex(exporter)
        }
        print("EVENT type=ready role=server remote=\(connection.endpoint) tls_version=\(version) alpn=\(alpn) exporter_sha256=\(exporterSha) elapsed_ms=\(elapsedMs)")
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                let text = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
                print("EVENT type=app-data role=server remote=\(connection.endpoint) bytes=\(data.count) text=\"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                connection.send(content: "ack\n".data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if isComplete || error != nil {
                self?.finish(connection)
            }
        }
    }

    /// E03-04 experiment 2: in-band challenge fallback (D-15's recorded fallback for stacks that
    /// cannot produce an RFC 9266 exporter, e.g. Conscrypt on Android API 29/30). Sends 32 random
    /// bytes over the already-established, mutually-authenticated TLS session, reads back a
    /// length-prefixed ECDSA signature over those bytes from the peer's pinned private key, and
    /// verifies it against the public key captured during this connection's verify_block.
    private func runChallenge(_ connection: NWConnection) {
        guard let peerKey = PendingPeerKeyStore.shared.takeAndClear() else {
            print("EVENT type=challenge-error role=server remote=\(connection.endpoint) error=\"no peer key captured\"")
            connection.cancel()
            return
        }
        let challenge = randomChallenge()
        connection.send(content: challenge, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                print("EVENT type=challenge-error role=server remote=\(connection.endpoint) error=\"send failed: \(error)\"")
                connection.cancel()
                return
            }
            self.receiveExact(connection, length: 1) { lengthByte in
                guard let lengthByte, let sigLength = lengthByte.first else {
                    print("EVENT type=challenge-error role=server remote=\(connection.endpoint) error=\"no signature length byte\"")
                    connection.cancel()
                    return
                }
                self.receiveExact(connection, length: Int(sigLength)) { signature in
                    guard let signature else {
                        print("EVENT type=challenge-error role=server remote=\(connection.endpoint) error=\"short signature read\"")
                        connection.cancel()
                        return
                    }
                    let match = verifyChallengeSignature(challenge: challenge, signatureDER: signature, publicKey: peerKey)
                    print("EVENT type=challenge-verified role=server remote=\(connection.endpoint) match=\(match) challenge_sha256=\(sha256Hex(challenge))")
                    let ack: Data = Data([match ? 0x01 : 0x00])
                    connection.send(content: ack, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        })
    }

    private func receiveExact(_ connection: NWConnection, length: Int, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
            if let data, data.count == length {
                completion(data)
            } else {
                completion(nil)
            }
        }
    }

    private func finish(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.lock()
        openConnections.removeValue(forKey: id)
        terminalCount += 1
        let count = terminalCount
        lock.unlock()
        if let exitAfter, count >= exitAfter {
            print("EVENT type=exit-after-reached count=\(count)")
            listener.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
        }
    }
}
