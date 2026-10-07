import AppKit
import Testing

@testable import FeatureClipboard
@testable import TandemApp
@testable import TandemProtocol

/// E31-11 tdd (unit): ``PushClipboardViewModel`` sending the CURRENT pasteboard item through a
/// real ``ClipboardSender`` (E31-04) built from `FeatureClipboard`'s own `FakePasteboardSource`
/// (E31-02) and the E12-12 `FakeTandemSession` -- the exact same concealed/transient skip
/// (E31-03) and 1 MiB cap apply as the automatic poller, without waiting for a poll tick.
@Suite("PushClipboardViewModel")
struct PushClipboardViewModelTests {
    // MARK: - pushClipboardAction_plainTextItem_sendsClipboardText

    @Test
    func pushClipboardAction_plainTextItem_sendsClipboardText() async throws {
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        source.setString("hello", forType: .string)
        let session = FakeTandemSession()
        let sender = ClipboardSender(source: source, clock: ManualTestClock(), session: session)
        let viewModel = await PushClipboardViewModel(sender: sender)

        await viewModel.select()

        var attempts = 0
        while await session.sent.count < 1, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        let sent = await session.sent
        #expect(sent.count == 1)
        #expect(sent.first?.channel == .clipboard)
        guard case .clipboardText(let clipboardText) = sent.first?.payload else {
            Issue.record("expected a clipboardText payload, got \(String(describing: sent.first?.payload))")
            return
        }
        #expect(clipboardText.text == "hello")
        var statusAttempts = 0
        while await viewModel.statusMessage == nil, statusAttempts < 10_000 {
            await Task.yield()
            statusAttempts += 1
        }
        #expect(await viewModel.statusMessage == PushClipboardViewModel.sentMessage)
    }

    // MARK: - pushClipboardAction_concealedItem_noFrameAndStatusNotSentProtectedItem

    @Test
    func pushClipboardAction_concealedItem_noFrameAndStatusNotSentProtectedItem() async throws {
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let source = FakePasteboardSource(changeCount: 0, types: [.string, concealedType])
        source.setString("secret", forType: .string)
        let session = FakeTandemSession()
        let sender = ClipboardSender(source: source, clock: ManualTestClock(), session: session)
        let viewModel = await PushClipboardViewModel(sender: sender)

        await viewModel.select()

        var attempts = 0
        while await viewModel.statusMessage == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.statusMessage == "Not sent: protected item")
        #expect(await session.sent.isEmpty)
    }

    // MARK: - pushClipboardAction_overLimitItem_noFrameAndStatusShowsSizeHint

    @Test
    func pushClipboardAction_overLimitItem_noFrameAndStatusShowsSizeHint() async throws {
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let text = String(repeating: "a", count: ClipboardSender.maxTextBytes + 1)
        source.setString(text, forType: .string)
        let session = FakeTandemSession()
        let sender = ClipboardSender(source: source, clock: ManualTestClock(), session: session)
        let viewModel = await PushClipboardViewModel(sender: sender)

        await viewModel.select()

        var attempts = 0
        while await viewModel.statusMessage == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.statusMessage == ClipboardSender.tooLargeHint)
        #expect(await session.sent.isEmpty)
    }

    // MARK: - pushClipboardViewModel_phoneClipReceived_statusReceivedFromPhone

    @Test
    func pushClipboardViewModel_phoneClipReceived_statusReceivedFromPhone() async throws {
        let clipboard = ActiveClipboard()
        let viewModel = await PushClipboardViewModel(clipboard: clipboard)

        clipboard.reportReceived()

        var attempts = 0
        while await viewModel.statusMessage == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.statusMessage == PushClipboardViewModel.receivedMessage)
    }
}
