import AppKit
import Testing
@testable import FeatureClipboard
@testable import TandemProtocol
@testable import TandemTestSupport

/// E31-14: ``ClipboardLoopGuard``, shared between ``ClipboardSender`` and ``PasteboardWriter``,
/// prevents the phone-to-Mac-to-phone echo -- the Mac counterpart to Android's own
/// `ClipboardLoopGuard` (E31-08).
@Suite("ClipboardLoopGuard", .serialized)
struct ClipboardLoopGuardTests {

    private func makeHarness(
        clock: ManualTestClock,
        source: FakePasteboardSource,
        session: FakeTandemSession
    ) -> (sender: ClipboardSender, writer: PasteboardWriter) {
        let loopGuard = ClipboardLoopGuard()
        let sender = ClipboardSender(source: source, clock: clock, session: session, loopGuard: loopGuard)
        let writer = PasteboardWriter(source: source, session: session, loopGuard: loopGuard)
        return (sender, writer)
    }

    @Test
    func macLoopGuard_receivedClipRedetected_notSent() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let session = FakeTandemSession()
        let (sender, writer) = makeHarness(clock: clock, source: source, session: session)

        await sender.start()
        await writer.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        var clipboardText = Tandem_V1_ClipboardText()
        clipboardText.originTag = "android"
        clipboardText.text = "hello from phone"
        await session.inject(InboundFrame(channel: .clipboard, seq: 0, ack: 0, payload: .clipboardText(clipboardText)))

        let wrote = await waitUntilTrue { source.string(forType: .string) == "hello from phone" }
        #expect(wrote)
        await realDelay(milliseconds: 20)

        clock.advance(by: PasteboardPoller.pollInterval)
        await realDelay(milliseconds: 20)

        #expect(await session.sent.isEmpty, "re-detecting the just-applied received write must not be sent back")
    }

    @Test
    func macLoopGuard_newContentAfterReceive_sentAtNextPoll() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let session = FakeTandemSession()
        let (sender, writer) = makeHarness(clock: clock, source: source, session: session)

        await sender.start()
        await writer.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        var clipboardText = Tandem_V1_ClipboardText()
        clipboardText.originTag = "android"
        clipboardText.text = "hello from phone"
        await session.inject(InboundFrame(channel: .clipboard, seq: 0, ack: 0, payload: .clipboardText(clipboardText)))

        let wrote = await waitUntilTrue { source.string(forType: .string) == "hello from phone" }
        #expect(wrote)
        await realDelay(milliseconds: 20)

        // Re-detection of the applied receive: skipped, exactly as above.
        #expect(await waitForParkedSleepers(clock, count: 1))
        clock.advance(by: PasteboardPoller.pollInterval)
        await realDelay(milliseconds: 20)
        #expect(await session.sent.isEmpty)

        // A genuinely new local change.
        source.setString("local change", forType: .string)
        #expect(await waitForParkedSleepers(clock, count: 1))
        clock.advance(by: PasteboardPoller.pollInterval)

        let sent = await waitUntilTrue { await session.sent.count == 1 }
        #expect(sent, "a genuinely new local change must be sent at the next poll")
        let frame = await session.sent[0]
        guard case .clipboardText(let sentText) = frame.payload else {
            Issue.record("expected a clipboardText payload, got \(String(describing: frame.payload))")
            return
        }
        #expect(sentText.text == "local change")
    }

    @Test
    func macLoopGuard_receivedAThenLocalBThenLocalA_aSent() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let session = FakeTandemSession()
        let (sender, writer) = makeHarness(clock: clock, source: source, session: session)

        await sender.start()
        await writer.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        // Receive A.
        var clipboardTextA = Tandem_V1_ClipboardText()
        clipboardTextA.originTag = "android"
        clipboardTextA.text = "content A"
        await session.inject(InboundFrame(channel: .clipboard, seq: 0, ack: 0, payload: .clipboardText(clipboardTextA)))
        let wroteA = await waitUntilTrue { source.string(forType: .string) == "content A" }
        #expect(wroteA)
        await realDelay(milliseconds: 20)

        // Re-detection of the applied receive of A: skipped.
        #expect(await waitForParkedSleepers(clock, count: 1))
        clock.advance(by: PasteboardPoller.pollInterval)
        await realDelay(milliseconds: 20)
        #expect(await session.sent.isEmpty)

        // Local B sent.
        source.setString("content B", forType: .string)
        #expect(await waitForParkedSleepers(clock, count: 1))
        clock.advance(by: PasteboardPoller.pollInterval)
        let bSent = await waitUntilTrue { await session.sent.count == 1 }
        #expect(bSent)

        // Local A again: the guard from receiving A no longer applies once B was sent, so this
        // genuinely new local change (a new changeCount, same content as the earlier receive) is
        // sent normally.
        source.setString("content A", forType: .string)
        #expect(await waitForParkedSleepers(clock, count: 1))
        clock.advance(by: PasteboardPoller.pollInterval)
        let aSent = await waitUntilTrue { await session.sent.count == 2 }
        #expect(aSent, "a later local change back to A's own content must be sent, not blocked")

        let sentTexts: [String] = await session.sent.compactMap { frame in
            guard case .clipboardText(let text) = frame.payload else { return nil }
            return text.text
        }
        #expect(sentTexts == ["content B", "content A"])
    }
}
