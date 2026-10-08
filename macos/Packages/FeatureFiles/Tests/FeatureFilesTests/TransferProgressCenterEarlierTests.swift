import Foundation
import Testing
import TandemTestSupport
@testable import FeatureFiles

@MainActor
struct TransferProgressCenterEarlierTests {
    private let endedAt = Date(timeIntervalSince1970: 1_000)

    private func makeCenter() -> TransferProgressCenter {
        let endedAt = endedAt
        return TransferProgressCenter(clock: ManualTestClock(), now: { endedAt })
    }

    @Test
    func transfersEarlier_transferEnded_movesFromActiveToEarlierNewestFirst() async {
        let center = makeCenter()
        await center.began(id: "a", name: "a.mov", totalBytes: 10, cancel: {})
        await center.began(id: "b", name: "b.pdf", totalBytes: 20, cancel: {})

        await center.ended(id: "a")
        await center.ended(id: "b")

        #expect(center.rows.isEmpty)
        #expect(center.earlier.map(\.id) == ["b", "a"])
        #expect(center.earlier.first?.endedAt == endedAt)
        #expect(center.earlier.first?.totalBytes == 20)
    }

    @Test
    func transfersEarlier_cancelledTransfer_isNotListed() async {
        let center = makeCenter()
        await center.began(id: "a", name: "a.mov", totalBytes: 10, cancel: {})
        await center.rows.first?.cancel()

        await center.ended(id: "a")

        #expect(center.earlier.isEmpty)
    }

    @Test
    func transfersEarlier_moreThanLimit_keepsNewestTwenty() async {
        let center = makeCenter()
        for index in 0..<25 {
            await center.began(id: "t\(index)", name: "f\(index)", totalBytes: 1, cancel: {})
            await center.ended(id: "t\(index)")
        }

        #expect(center.earlier.count == 20)
        #expect(center.earlier.first?.id == "t24")
    }

    @Test
    func transfersSection_stateText_countsActiveTransfers() {
        #expect(TransfersSectionView.stateText(activeCount: 0) == "Nothing in progress.")
        #expect(TransfersSectionView.stateText(activeCount: 1) == "1 in progress.")
        #expect(TransfersSectionView.stateText(activeCount: 3) == "3 in progress.")
    }

    @Test
    func transfersEarlier_withoutClock_timeTextEmpty() {
        let transfer = EarlierTransfer(id: "a", name: "a", totalBytes: 1, endedAt: nil)
        #expect(transfer.timeText().isEmpty)
    }
}
