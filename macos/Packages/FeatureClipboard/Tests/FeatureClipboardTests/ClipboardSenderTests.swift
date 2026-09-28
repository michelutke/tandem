import AppKit
import CryptoKit
import Foundation
import Testing
@testable import FeatureClipboard
@testable import TandemProtocol
@testable import TandemTestSupport

/// E31-04: ``ClipboardSender`` polls the pasteboard (via ``FakePasteboardSource``, E31-02) and
/// sends a qualifying plain-text change as `ClipboardText` on the fake `TandemSession`'s CLIPBOARD
/// channel (E12-12), enforcing the concealed-type skip (E31-03) and the 1 MiB size cap
/// (docs/protocol/SPEC.md #clipboard-channel) before ever sending.
@Suite("ClipboardSender", .serialized)
struct ClipboardSenderTests {

    @Test
    func clipboardSender_textExactly1MiB_sentWithOriginMacosAndSpecHash() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let text = String(repeating: "a", count: ClipboardSender.maxTextBytes)
        source.setString(text, forType: .string)
        let session = FakeTandemSession()
        let sender = ClipboardSender(source: source, clock: clock, session: session)

        await sender.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        source.changeCount = 1
        clock.advance(by: PasteboardPoller.pollInterval)

        let sent = await waitUntilTrue { await session.sent.count == 1 }
        #expect(sent, "expected exactly one ClipboardText frame sent")

        let frame = await session.sent[0]
        #expect(frame.channel == .clipboard)
        guard case .clipboardText(let clipboardText) = frame.payload else {
            Issue.record("expected a clipboardText payload, got \(String(describing: frame.payload))")
            return
        }
        #expect(clipboardText.originTag == "macos")
        #expect(clipboardText.text == text)
        let expectedHash = Data(SHA256.hash(data: Data(text.utf8)))
        #expect(clipboardText.contentHash == expectedHash)
    }

    @Test
    func clipboardSender_oneByteOver1MiB_noFrameSent() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let text = String(repeating: "a", count: ClipboardSender.maxTextBytes + 1)
        source.setString(text, forType: .string)
        let session = FakeTandemSession()
        let sender = ClipboardSender(source: source, clock: clock, session: session)

        await sender.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        source.changeCount = 1
        clock.advance(by: PasteboardPoller.pollInterval)

        // Give the poll tick's callback a chance to run, then confirm nothing was ever sent --
        // no partial or truncated frame, not even a smaller one.
        let hinted = await waitUntilTrue { await sender.hintsShown.count == 1 }
        #expect(hinted)
        #expect(await session.sent.isEmpty, "an over-cap item must never be sent, truncated or not")
    }

    @Test
    func clipboardSender_overLimitItemPolledTwice_sizeHintShownOnce() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let text = String(repeating: "a", count: ClipboardSender.maxTextBytes + 1)
        source.setString(text, forType: .string)
        let session = FakeTandemSession()
        let sender = ClipboardSender(source: source, clock: clock, session: session)

        await sender.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        // First tick: a genuinely new oversized item -- warned once.
        source.changeCount = 1
        clock.advance(by: PasteboardPoller.pollInterval)
        let warnedOnce = await waitUntilTrue { await sender.hintsShown.count == 1 }
        #expect(warnedOnce)

        // The same item sits on the pasteboard across many further ticks (changeCount unchanged):
        // the hint must not repeat.
        #expect(await waitForParkedSleepers(clock, count: 1))
        for _ in 0..<5 {
            clock.advance(by: PasteboardPoller.pollInterval)
            #expect(await waitForParkedSleepers(clock, count: 1))
        }
        await realDelay(milliseconds: 20)
        #expect(await sender.hintsShown == [ClipboardSender.tooLargeHint])
        #expect(await session.sent.isEmpty)

        // A different oversized item (new changeCount) is warned about again.
        let otherText = String(repeating: "b", count: ClipboardSender.maxTextBytes + 2)
        source.setString(otherText, forType: .string)
        source.changeCount = 2
        clock.advance(by: PasteboardPoller.pollInterval)
        let warnedTwice = await waitUntilTrue { await sender.hintsShown.count == 2 }
        #expect(warnedTwice)
        #expect(await sender.hintsShown == [ClipboardSender.tooLargeHint, ClipboardSender.tooLargeHint])
    }

    @Test
    func clipboardSender_imageOnlyItem_noFrameSent() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.tiff])
        let session = FakeTandemSession()
        let sender = ClipboardSender(source: source, clock: clock, session: session)

        await sender.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        source.changeCount = 1
        clock.advance(by: PasteboardPoller.pollInterval)

        await realDelay(milliseconds: 20)
        #expect(await session.sent.isEmpty, "an item with no public.utf8-plain-text representation must never be sent")
        #expect(await sender.hintsShown.isEmpty)
    }
}
