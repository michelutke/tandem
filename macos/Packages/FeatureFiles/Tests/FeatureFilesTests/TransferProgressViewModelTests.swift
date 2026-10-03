import Foundation
import Testing
import TandemTestSupport
@testable import FeatureFiles

private let mebibyte: Int64 = 1_048_576

@MainActor
struct TransferProgressViewModelTests {
    @Test
    func macosProgressVm_threeMiBInThreeSeconds_reportsOneMiBPerSecond() {
        let clock = ManualTestClock()
        let viewModel = TransferProgressViewModel(id: "t1", name: "a.bin", totalBytes: 3 * mebibyte, clock: clock) {}

        for _ in 0..<3 {
            clock.advance(by: .seconds(1))
            viewModel.record(deliveredBytes: viewModel.deliveredBytes + mebibyte)
        }

        let speed = viewModel.progress.bytesPerSecond
        #expect(abs(speed - Double(mebibyte)) <= Double(mebibyte) * 0.01)
        #expect(viewModel.progress.percent == 100)
    }

    @Test
    func macosProgressVm_bytesFlowing_emitsBetween250msAnd1s() {
        let clock = ManualTestClock()
        let viewModel = TransferProgressViewModel(id: "t1", name: "a.bin", totalBytes: 3 * mebibyte, clock: clock) {}
        var emissionTimes: [Duration] = []

        for _ in 0..<30 {
            clock.advance(by: .milliseconds(100))
            viewModel.record(deliveredBytes: viewModel.deliveredBytes + mebibyte / 10)
            if emissionTimes.last != viewModel.progress.at { emissionTimes.append(viewModel.progress.at) }
        }

        #expect(emissionTimes.count > 2)
        for (earlier, later) in zip(emissionTimes, emissionTimes.dropFirst()) {
            #expect(later - earlier >= .milliseconds(250))
            #expect(later - earlier <= .seconds(1))
        }
    }

    @Test
    func macosProgressVm_cancel_invokesCancelFlowAndMarksCancelled() async {
        let clock = ManualTestClock()
        var cancelCalls = 0
        let viewModel = TransferProgressViewModel(id: "t1", name: "a.bin", totalBytes: 100, clock: clock) {
            cancelCalls += 1
        }

        await viewModel.cancel()

        #expect(cancelCalls == 1)
        #expect(viewModel.isCancelled)
    }
}
