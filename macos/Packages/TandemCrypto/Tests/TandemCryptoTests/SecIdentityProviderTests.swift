import Foundation
import Network
import Security
import Testing
@testable import TandemCrypto

/// `sec_identity_create` (over the `SecIdentity` `SecIdentityProvider` returns) needs the identity
/// key and certificate to already be paired in a real Keychain (spike E03-02,
/// docs/spikes/secure-enclave-identity.md); there is no way to fake a `SecIdentity`/`sec_identity_t`
/// value. Both tests here run against a throwaway file-target `SecItemKeychainStore`
/// (`TemporaryKeychain`, E10-07b, D-75) -- never the login keychain, and no signed host or
/// entitlement needed -- so they run unconditionally in plain `swift test`. `Network` is otherwise
/// off-limits in this package (E00-15's package-graph rule), but that rule only covers `Sources/`,
/// not `Tests/`; the production `SecIdentityProvider` type never imports it.
@Suite("SecIdentityProvider (hosted)", .timeLimit(.minutes(1)))
struct SecIdentityProviderHostedTests {

    @Test
    func secIdentity_hostedKeychainCertAndKey_secIdentityCreateReturnsNonNil() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let provider = SecIdentityProvider(keychainStore: keychain.store)

        let secIdentity = try provider.getOrCreateSecIdentity()

        #expect(sec_identity_create(secIdentity) != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func secIdentity_loopbackListenerAndClient_tls13HandshakeCompletes() async throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let provider = SecIdentityProvider(keychainStore: keychain.store)
        let secIdentity = try provider.getOrCreateSecIdentity()
        let identity = try #require(sec_identity_create(secIdentity))

        let harness = LoopbackHandshakeHarness()
        let listener = try Self.makeListener(identity: identity, harness: harness)
        defer { listener.cancel() }
        listener.start(queue: DispatchQueue(label: "e10-07-test-listener"))

        let port = try await harness.waitForListenerPort()
        let connection = Self.makeClientConnection(port: port, harness: harness)
        defer { connection.cancel() }
        connection.start(queue: DispatchQueue(label: "e10-07-test-client-connection"))

        try await harness.waitForBothReady()
    }

    /// A listener bound to a literal loopback endpoint (never `on:` a port alongside
    /// `requiredLocalEndpoint` -- spike E03-01 found the pair throws `POSIXErrorCode(rawValue: 22)`),
    /// TLS 1.3-only, presenting `identity` as its local identity.
    private static func makeListener(identity: sec_identity_t, harness: LoopbackHandshakeHarness) throws -> NWListener {
        let serverOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(serverOptions.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(serverOptions.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_local_identity(serverOptions.securityProtocolOptions, identity)

        let parameters = NWParameters(tls: serverOptions, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { await harness.markListenerReady(port: listener.port) }
            case .failed(let error):
                Task { await harness.fail(error) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task { await harness.markServerReady() }
                case .failed(let error):
                    Task { await harness.fail(error) }
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "e10-07-test-server-connection"))
        }
        return listener
    }

    /// A plain TLS 1.3 client with no local identity of its own -- this test only proves the
    /// E10-07 identity negotiates a TLS 1.3 handshake, not mTLS/pinning (E12-01/E12-02/E13-06's
    /// concern), so the verify block accepts the self-signed leaf unconditionally.
    private static func makeClientConnection(port: NWEndpoint.Port, harness: LoopbackHandshakeHarness) -> NWConnection {
        let clientOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(clientOptions.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(clientOptions.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_verify_block(clientOptions.securityProtocolOptions, { _, _, complete in
            complete(true)
        }, DispatchQueue(label: "e10-07-test-client-verify"))

        let parameters = NWParameters(tls: clientOptions, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { await harness.markClientReady() }
            case .failed(let error):
                Task { await harness.fail(error) }
            default:
                break
            }
        }
        return connection
    }
}

/// Coordinates the async readiness signals from the listener, its accepted server-side
/// connection, and the client connection in `secIdentity_loopbackListenerAndClient_...` above.
private actor LoopbackHandshakeHarness {
    private var listenerPortContinuation: CheckedContinuation<NWEndpoint.Port, Error>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var serverReady = false
    private var clientReady = false
    private var failure: Error?

    func waitForListenerPort() async throws -> NWEndpoint.Port {
        try await withCheckedThrowingContinuation { continuation in
            listenerPortContinuation = continuation
        }
    }

    func markListenerReady(port: NWEndpoint.Port?) {
        guard let listenerPortContinuation else { return }
        self.listenerPortContinuation = nil
        guard let port else {
            listenerPortContinuation.resume(throwing: LoopbackHandshakeHarnessError.noPort)
            return
        }
        listenerPortContinuation.resume(returning: port)
    }

    func markServerReady() {
        serverReady = true
        completeIfBothReady()
    }

    func markClientReady() {
        clientReady = true
        completeIfBothReady()
    }

    func fail(_ error: Error) {
        failure = error
        if let listenerPortContinuation {
            self.listenerPortContinuation = nil
            listenerPortContinuation.resume(throwing: error)
        }
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: error)
        }
    }

    func waitForBothReady() async throws {
        if let failure { throw failure }
        if serverReady, clientReady { return }
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
        }
    }

    private func completeIfBothReady() {
        guard serverReady, clientReady, let readyContinuation else { return }
        self.readyContinuation = nil
        readyContinuation.resume()
    }
}

private enum LoopbackHandshakeHarnessError: Error {
    case noPort
}
