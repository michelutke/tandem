import Foundation
import Testing
@testable import TandemTransport

/// E22-10 (`docs/planning/decisions.md` D-59, D-76, AC-13): every verify-callback rejection is
/// pre-pin-check by definition on the Mac listener, so it only ever bumps the aggregate counter --
/// never a per-connection banner, regardless of whether this Mac already has pinned peers.
@Suite("PinMismatchBannerGate")
struct PinMismatchBannerGateTests {

    @Test
    func gate_recordRejection_incrementsAggregateCounter() async throws {
        let gate = PinMismatchBannerGate()

        await gate.recordRejection()
        #expect(await gate.rejectionCount == 1)

        await gate.recordRejection()
        #expect(await gate.rejectionCount == 2)
    }
}
