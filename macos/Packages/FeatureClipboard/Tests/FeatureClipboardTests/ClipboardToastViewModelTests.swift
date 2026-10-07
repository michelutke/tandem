import Testing
@testable import FeatureClipboard
@testable import TandemTestSupport

@MainActor
struct ClipboardToastViewModelTests {
    private final class Recorder {
        var shown: [String?] = []
    }

    private func makeViewModel(
        clock: ManualTestClock,
        deviceName: String?,
        recorder: Recorder
    ) -> ClipboardToastViewModel {
        ClipboardToastViewModel(
            clock: clock,
            deviceName: { deviceName },
            present: { recorder.shown.append($0) }
        )
    }

    private func waitForSleepers(_ clock: ManualTestClock, count: Int) async -> Bool {
        await waitUntil { clock.pendingSleeperCountForTesting >= count }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    @Test func text_withDeviceName_namesThePhone() {
        #expect(ClipboardToastViewModel.text(deviceName: "Google Pixel 8 Pro") == "Copied from Google Pixel 8 Pro.")
    }

    @Test(arguments: [nil, ""] as [String?])
    func text_missingDeviceName_fallsBackToYourPhone(name: String?) {
        #expect(ClipboardToastViewModel.text(deviceName: name) == "Copied from your phone.")
    }

    @Test func clipboardReceived_afterHold_hidesToast() async {
        let clock = ManualTestClock()
        let recorder = Recorder()
        let viewModel = makeViewModel(clock: clock, deviceName: "Pixel 9", recorder: recorder)

        viewModel.clipboardReceived()
        #expect(recorder.shown == ["Copied from Pixel 9."])
        #expect(await waitForSleepers(clock, count: 1))
        clock.advance(by: ClipboardToastViewModel.holdDuration)

        #expect(await waitUntil { recorder.shown.last == .some(nil) })
    }

    @Test func clipboardReceived_secondClipBeforeHold_restartsTimer() async {
        let clock = ManualTestClock()
        let recorder = Recorder()
        let viewModel = makeViewModel(clock: clock, deviceName: "Pixel 9", recorder: recorder)

        viewModel.clipboardReceived()
        #expect(await waitForSleepers(clock, count: 1))
        clock.advance(by: .milliseconds(1000))
        viewModel.clipboardReceived()
        #expect(await waitUntil { clock.pendingSleeperCountForTesting == 1 })
        clock.advance(by: .milliseconds(1000))

        #expect(recorder.shown == ["Copied from Pixel 9.", "Copied from Pixel 9."])
        clock.advance(by: .milliseconds(800))
        #expect(await waitUntil { recorder.shown.last == .some(nil) })
    }
}
