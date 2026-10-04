import Foundation
import Synchronization
import TandemCrypto
@testable import TandemTransport

enum MediaFrameFixtures {
    static let ticket = Data((0..<32).map { UInt8($0) })
    static let mirrorSessionId = Data((0..<16).map { UInt8(0xA0 + $0) })

    /// Length-prefixed bare `MediaHello` (field 1, bytes), as the phone sends it.
    static func mediaHelloFrame(ticket: Data, mirrorSessionId: Data = mirrorSessionId) -> Data {
        var body = Data([0x0A, UInt8(ticket.count)]) + ticket
        if !mirrorSessionId.isEmpty { body += Data([0x12, UInt8(mirrorSessionId.count)]) + mirrorSessionId }
        return lengthPrefixed(body)
    }

    /// Length-prefixed control `Envelope` carrying `VersionHello { major: 1 }` (channel 1, seq 1).
    static let versionHelloFrame = lengthPrefixed(Data([0x08, 0x01, 0x10, 0x01, 0x22, 0x02, 0x08, 0x01]))

    static var validHelloFrame: Data { mediaHelloFrame(ticket: ticket) }

    static func lengthPrefixed(_ body: Data) -> Data {
        let length = UInt32(body.count)
        let prefix = [length >> 24, length >> 16 & 0xFF, length >> 8 & 0xFF, length & 0xFF]
        return Data(prefix.map { UInt8($0) }) + body
    }
}

/// Single-use ticket book standing in for FeatureMirror's `MediaTicketValidator` (E60-08, tested in
/// that package): one issued ticket, bound to a session and peer, consumed on first success.
final class OneShotTicketValidator: MediaTicketValidating, Sendable {
    private struct State {
        var consumed = false
        var calls = 0
    }

    let sessionID = UUID()
    private let ticket: Data
    private let peer: SpkiFingerprint?
    private let state = Mutex(State())

    init(ticket: Data = MediaFrameFixtures.ticket, peer: SpkiFingerprint? = nil) {
        self.ticket = ticket
        self.peer = peer
    }

    var callCount: Int { state.withLock { $0.calls } }

    func validate(ticket presented: Data?, presentingSpki: SpkiFingerprint) -> Result<UUID, MediaTicketRejectReason> {
        state.withLock { state in
            state.calls += 1
            guard let presented, presented.count == 32 else { return .failure(.missing) }
            guard presented == ticket else { return .failure(.consumed) }
            if let peer, !peer.matches(presentingSpki) { return .failure(.peerMismatch) }
            guard !state.consumed else { return .failure(.consumed) }
            state.consumed = true
            return .success(sessionID)
        }
    }
}

/// Yields scripted chunks one pull at a time and counts the pulls, so a test can prove nothing past
/// the first frame was read.
final class ScriptedConnection: ByteStreamConnection, Sendable {
    private struct Script {
        var chunks: [Data]
        var pulls = 0
        var cancelled = false
    }

    private let script: Mutex<Script>
    let state = AsyncStream<ConnectionState> { $0.finish() }

    init(chunks: [Data]) {
        script = Mutex(Script(chunks: chunks))
    }

    var pulls: Int { script.withLock { $0.pulls } }
    var cancelled: Bool { script.withLock { $0.cancelled } }

    func send(_ data: Data) async throws {}

    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(unfolding: { [self] in
            script.withLock { script in
                script.pulls += 1
                return script.chunks.isEmpty ? nil : script.chunks.removeFirst()
            }
        })
    }

    func cancel() {
        script.withLock { $0.cancelled = true }
    }
}
