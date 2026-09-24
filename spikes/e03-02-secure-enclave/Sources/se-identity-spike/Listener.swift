import Foundation
import Network
import Security

/// Builds `NWProtocolTLS.Options` with `identity.secIdentity` as the listener's local identity.
/// Peer authentication is required (mTLS shape, per acceptance criteria) but the verify block
/// accepts any client certificate -- pin-matching semantics are E03-01's spike, this one is
/// only about whether an SE-backed `sec_identity` works and how fast it is.
func makeListenerTLSOptions(identity: GeneratedIdentity, log: @escaping (String) -> Void) -> NWProtocolTLS.Options {
    let options = NWProtocolTLS.Options()
    let sec = options.securityProtocolOptions

    sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
    sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)

    guard let secIdentityRef = sec_identity_create(identity.secIdentity) else {
        fatalError("sec_identity_create failed for local identity (backing=\(identity.backing))")
    }
    sec_protocol_options_set_local_identity(sec, secIdentityRef)
    sec_protocol_options_set_peer_authentication_required(sec, true)
    sec_protocol_options_set_tls_tickets_enabled(sec, false)
    sec_protocol_options_set_tls_resumption_enabled(sec, false)

    let queue = DispatchQueue(label: "verify-block")
    sec_protocol_options_set_verify_block(sec, { _, _, complete in
        complete(true)
    }, queue)

    return options
}

final class SpikeListener {
    private let listener: NWListener
    private let onReady: (Double) -> Void
    private let onFailed: (String) -> Void
    private let backing: KeyBacking

    init(port: UInt16, identity: GeneratedIdentity, log: @escaping (String) -> Void, onReady: @escaping (Double) -> Void, onFailed: @escaping (String) -> Void) throws {
        let options = makeListenerTLSOptions(identity: identity, log: log)
        let params = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        self.backing = identity.backing
        self.onReady = onReady
        self.onFailed = onFailed
        self.listener = try NWListener(using: params)
    }

    func start(log: @escaping (String) -> Void) {
        listener.stateUpdateHandler = { state in
            log("EVENT type=listener-state backing=\(self.backing) state=\(state)")
            if case .failed(let error) = state {
                log("EVENT type=listener-failed backing=\(self.backing) error=\"\(error)\"")
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, log: log)
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection, log: @escaping (String) -> Void) {
        let start = DispatchTime.now()
        log("EVENT type=accept-called backing=\(backing) remote=\(connection.endpoint)")
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            switch state {
            case .ready:
                log("EVENT type=ready role=server backing=\(self.backing) remote=\(connection.endpoint) elapsed_ms=\(elapsedMs)")
                self.onReady(elapsedMs)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { _, _, _, _ in
                    connection.cancel()
                }
            case .failed(let error):
                log("EVENT type=failed role=server backing=\(self.backing) error=\"\(error)\" elapsed_ms=\(elapsedMs)")
                self.onFailed("\(error)")
            case .cancelled:
                break
            default:
                log("EVENT type=state role=server backing=\(self.backing) state=\(state) elapsed_ms=\(elapsedMs)")
            }
        }
        connection.start(queue: .main)
    }
}
