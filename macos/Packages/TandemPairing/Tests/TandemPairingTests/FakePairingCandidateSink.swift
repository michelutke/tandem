import Foundation
@testable import TandemPairing

/// A ``PairingCandidateSink`` fake recording every call, in order, for assertions -- stands in
/// for the real candidate connection (no `TandemSession`/`TandemProtocol` wiring exists yet), the
/// way ``SpyPairRequestVerifier`` stands in for the real proof check.
final class FakePairingCandidateSink: PairingCandidateSink, @unchecked Sendable {
    enum Call: Equatable {
        case pairChallenge(Data)
        case pairRejected(PairRejectedWireReason)
        case closePairingFailed
        case pairAccepted
        case commitment(Data)
        case reveal(Data)
        case manualPairResult
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func sendPairChallenge(_ challenge: Data) async throws {
        record(.pairChallenge(challenge))
    }

    func sendPairRejected(_ reason: PairRejectedWireReason) async throws {
        record(.pairRejected(reason))
    }

    func closePairingFailed() async {
        record(.closePairingFailed)
    }

    func sendPairAccepted() async throws {
        record(.pairAccepted)
    }

    func sendCommitment(_ hash: Data) async throws {
        record(.commitment(hash))
    }

    func sendReveal(_ nonce: Data) async throws {
        record(.reveal(nonce))
    }

    func sendManualPairResult() async throws {
        record(.manualPairResult)
    }

    private func record(_ call: Call) {
        lock.lock()
        recordedCalls.append(call)
        lock.unlock()
    }
}
