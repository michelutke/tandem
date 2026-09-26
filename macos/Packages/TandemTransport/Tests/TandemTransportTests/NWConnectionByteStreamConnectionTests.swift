import Foundation
import Network
import Security
import Testing
import TandemCrypto
@testable import TandemTransport

/// ``NWConnectionByteStreamConnection`` (E12-12): the real "Network.framework adapter"
/// ``ByteStreamConnection``'s own kdoc names, tested directly over a real loopback mTLS pair (not
/// through ``NWListenerFactory``'s automatic session wiring, so raw bytes sent here are never
/// mistaken for protocol frames by a `ChannelMultiplexer`). Both ends use `TemporaryKeychain`
/// (E10-07b, D-75) identities -- never the login keychain -- and an accept-all verify block, since
/// the real E12-02 pin decision is exercised elsewhere (`VerifyBlockLoopbackTests`).
@Suite("NWConnectionByteStreamConnection (hosted)", .serialized)
struct NWConnectionByteStreamConnectionTests {

    @Test(.timeLimit(.minutes(1)))
    func adapter_sendOverLoopback_peerReceivesByteIdenticalData() async throws {
        let (client, server) = try await Self.makeReadyPair()
        defer {
            client.cancel()
            server.cancel()
        }

        let payload = Data("hello over a real NWConnection".utf8)
        var serverIterator = server.receive().makeAsyncIterator()

        try await client.send(payload)
        let received = try await serverIterator.next()

        #expect(received == payload)
    }

    @Test(.timeLimit(.minutes(1)))
    func adapter_multipleSendsOverLoopback_arriveInOrder() async throws {
        let (client, server) = try await Self.makeReadyPair()
        defer {
            client.cancel()
            server.cancel()
        }

        let first = Data("first".utf8)
        let second = Data("second".utf8)
        var serverIterator = server.receive().makeAsyncIterator()

        try await client.send(first)
        try await client.send(second)

        var collected = Data()
        while collected.count < first.count + second.count {
            guard let chunk = try await serverIterator.next() else { break }
            collected.append(chunk)
        }

        #expect(collected == first + second)
    }

    @Test(.timeLimit(.minutes(1)))
    func adapter_localCancel_peerObservesReceiveEndAndCancelledState() async throws {
        let (client, server) = try await Self.makeReadyPair()
        defer {
            client.cancel()
            server.cancel()
        }

        async let cancelledState: ConnectionState? = {
            for await state in client.state where state != .ready {
                return state
            }
            return nil
        }()

        client.cancel()

        let observed = try #require(await cancelledState)
        #expect(observed == .cancelled)
    }

    // MARK: - Harness

    /// Builds a real loopback listener + client mTLS pair, waits for both sides to reach `.ready`,
    /// and returns each wrapped in its own ``NWConnectionByteStreamConnection`` with `.ready`
    /// already reported on its `state` stream.
    private static func makeReadyPair() async throws -> (
        client: NWConnectionByteStreamConnection,
        server: NWConnectionByteStreamConnection
    ) {
        let serverKeychain = try TemporaryKeychain()
        let clientKeychain = try TemporaryKeychain()
        let serverIdentity = try serverKeychain.makeSecIdentity()
        let clientIdentity = try clientKeychain.makeSecIdentity()

        let listener = try Self.makeAcceptAllListener(identity: serverIdentity)
        let serverAdapterBox = ServerAdapterBox()
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = Self.makeAdapterStateHandler(connection: connection, box: serverAdapterBox)
            connection.start(queue: .global())
        }
        let port = try await Self.waitForListenerPort(listener)

        let clientConnection = Self.makeClientConnection(port: port, identity: clientIdentity)
        let clientAdapter = NWConnectionByteStreamConnection(connection: clientConnection)
        clientConnection.stateUpdateHandler = { state in
            switch state {
            case .ready: clientAdapter.reportReady()
            case .failed(let error): clientAdapter.reportFailed("\(error)")
            case .cancelled: clientAdapter.reportCancelled()
            default: break
            }
        }
        clientConnection.start(queue: .global())

        var clientReadyIterator = clientAdapter.state.makeAsyncIterator()
        guard await clientReadyIterator.next() == .ready else {
            throw NWConnectionByteStreamConnectionTestError.neverReady
        }

        let serverAdapter = try await serverAdapterBox.waitForAdapter(timeout: 5)
        listener.cancel()
        return (clientAdapter, serverAdapter)
    }

    private static func makeAdapterStateHandler(
        connection: NWConnection,
        box: ServerAdapterBox
    ) -> @Sendable (NWConnection.State) -> Void {
        let adapter = NWConnectionByteStreamConnection(connection: connection)
        return { state in
            switch state {
            case .ready:
                adapter.reportReady()
                box.set(adapter)
            case .failed(let error):
                adapter.reportFailed("\(error)")
            case .cancelled:
                adapter.reportCancelled()
            default:
                break
            }
        }
    }

    private static func makeAcceptAllListener(identity: SecIdentity) throws -> NWListener {
        guard let secIdentity = sec_identity_create(identity) else {
            throw NWConnectionByteStreamConnectionTestError.invalidIdentity
        }
        let tlsOptions = NWProtocolTLS.Options()
        let sec = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_local_identity(sec, secIdentity)
        sec_protocol_options_set_peer_authentication_required(sec, true)
        sec_protocol_options_add_tls_application_protocol(sec, tandemALPN)
        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, .global())

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        return try NWListener(using: parameters, on: .any)
    }

    private static func makeClientConnection(port: NWEndpoint.Port, identity: SecIdentity) -> NWConnection {
        let options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_add_tls_application_protocol(sec, tandemALPN)
        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, .global())

        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        return NWConnection(host: "127.0.0.1", port: port, using: parameters)
    }

    private static func waitForListenerPort(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let resumeGuard = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: NWConnectionByteStreamConnectionTestError.noPort)
                        return
                    }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard resumeGuard.tryResume() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }
}

enum NWConnectionByteStreamConnectionTestError: Error {
    case invalidIdentity
    case noPort
    case neverReady
}

/// Lock-protected "resume this continuation exactly once" latch (mirrors `ListenerLoopbackTests`'
/// own `ResumeGuard`, kept file-local to avoid a cross-test-file dependency).
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

/// Hands the server-side adapter, built inside a `newConnectionHandler` closure, out to the
/// `async` test body waiting on it.
private final class ServerAdapterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var adapter: NWConnectionByteStreamConnection?
    private var continuation: CheckedContinuation<NWConnectionByteStreamConnection, Error>?

    func set(_ value: NWConnectionByteStreamConnection) {
        lock.lock()
        adapter = value
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func waitForAdapter(timeout: TimeInterval) async throws -> NWConnectionByteStreamConnection {
        if let existing = existingAdapter() {
            return existing
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.storeContinuation(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.timeOutPendingContinuation()
            }
        }
    }

    private func existingAdapter() -> NWConnectionByteStreamConnection? {
        lock.lock()
        defer { lock.unlock() }
        return adapter
    }

    private func storeContinuation(_ continuation: CheckedContinuation<NWConnectionByteStreamConnection, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func timeOutPendingContinuation() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: NWConnectionByteStreamConnectionTestError.neverReady)
    }
}
