import Foundation
import Testing
import TandemStore
import TandemTestSupport
@testable import FeatureFiles

@MainActor
struct TransferProgressCenterEarlierTests {
    private let endedAt = Date(timeIntervalSince1970: 1_000)

    private func makeCenter(history: (any TransferHistoryStore)? = nil) -> TransferProgressCenter {
        let endedAt = endedAt
        return TransferProgressCenter(clock: ManualTestClock(), now: { endedAt }, history: history)
    }

    @Test
    func transfersEarlier_transferEnded_movesFromActiveToEarlierNewestFirst() async {
        let center = makeCenter()
        await center.began(id: "a", name: "a.mov", totalBytes: 10, direction: .phoneToMac, cancel: {})
        await center.began(id: "b", name: "b.pdf", totalBytes: 20, direction: .macToPhone, cancel: {})

        await center.ended(id: "a", outcome: .completed)
        await center.ended(id: "b", outcome: .completed)

        #expect(center.rows.isEmpty)
        #expect(center.earlier.map(\.id) == ["b", "a"])
        #expect(center.earlier.first?.endedAt == endedAt)
        #expect(center.earlier.first?.totalBytes == 20)
    }

    @Test
    func transfersEarlier_cancelledTransfer_isListedWithCancelledState() async {
        let center = makeCenter()
        await center.began(id: "a", name: "a.mov", totalBytes: 10, direction: .phoneToMac, cancel: {})

        await center.ended(id: "a", outcome: .cancelled)

        #expect(center.earlier.map(\.stateText) == ["Cancelled"])
    }

    @Test
    func transfersEarlier_direction_isKept() async {
        let center = makeCenter()
        await center.began(id: "a", name: "a.mov", totalBytes: 10, direction: .macToPhone, cancel: {})
        await center.began(id: "b", name: "b.mov", totalBytes: 10, direction: .phoneToMac, cancel: {})
        await center.ended(id: "a", outcome: .completed)
        await center.ended(id: "b", outcome: .failed(reason: "ioError"))

        #expect(center.earlier.map(\.directionText) == ["To Mac", "To phone"])
        #expect(center.earlier.first?.stateText == "Failed")
    }

    @Test
    func transfersEarlier_moreThanLimit_keepsNewestTwoHundred() async {
        let center = makeCenter()
        for index in 0..<205 {
            await center.began(id: "t\(index)", name: "f\(index)", totalBytes: 1, direction: .phoneToMac, cancel: {})
            await center.ended(id: "t\(index)", outcome: .completed)
        }

        #expect(center.earlier.count == 200)
        #expect(center.earlier.first?.id == "t204")
    }

    @Test
    func transfersEarlier_loadEarlier_readsPersistedRecordsNewestFirst() async {
        let store = InMemoryTransferHistoryStore()
        await store.append(TransferRecord(
            id: "old", direction: .phoneToMac, name: "old.pdf", sizeBytes: 5, finishedAtMs: 1_000, outcome: .completed
        ))
        await store.append(TransferRecord(
            id: "new", direction: .macToPhone, name: "new.pdf", sizeBytes: 6, finishedAtMs: 2_000, outcome: .cancelled
        ))
        let center = makeCenter(history: store)

        await center.loadEarlier()

        #expect(center.earlier.map(\.id) == ["new", "old"])
        #expect(center.earlier.first?.direction == .macToPhone)
        #expect(center.earlier.first?.outcome == .cancelled)
    }

    @Test
    func transfersEarlier_transferEnded_isPersisted() async throws {
        let store = InMemoryTransferHistoryStore()
        let center = makeCenter(history: store)
        await center.began(id: "a", name: "a.mov", totalBytes: 10, direction: .phoneToMac, cancel: {})

        await center.ended(id: "a", outcome: .completed)

        let stored = try await store.list()
        #expect(stored.map(\.id) == ["a"])
        #expect(stored.first?.finishedAtMs == 1_000_000)
    }

    @Test
    func transfersEarlier_clearEarlier_emptiesListAndStore() async throws {
        let store = InMemoryTransferHistoryStore()
        let center = makeCenter(history: store)
        await center.began(id: "a", name: "a.mov", totalBytes: 10, direction: .phoneToMac, cancel: {})
        await center.ended(id: "a", outcome: .completed)

        await center.clearEarlier()

        #expect(center.earlier.isEmpty)
        #expect(try await store.list().isEmpty)
    }

    @Test
    func transfersSection_stateText_countsActiveTransfers() {
        #expect(TransfersSectionView.stateText(activeCount: 0) == "Nothing in progress.")
        #expect(TransfersSectionView.stateText(activeCount: 1) == "1 in progress.")
        #expect(TransfersSectionView.stateText(activeCount: 3) == "3 in progress.")
    }

    @Test
    func transfersEarlier_withoutClock_timeTextEmpty() {
        let transfer = EarlierTransfer(
            id: "a", name: "a", totalBytes: 1, endedAt: nil, direction: .phoneToMac, outcome: .completed
        )
        #expect(transfer.timeText().isEmpty)
    }
}
