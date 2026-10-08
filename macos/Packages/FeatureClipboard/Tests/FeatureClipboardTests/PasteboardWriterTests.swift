import AppKit
import Foundation
import Testing
@testable import FeatureClipboard
@testable import TandemProtocol

/// E31-13: ``PasteboardWriter`` reads `ClipboardText` off the fake `TandemSession`'s CLIPBOARD
/// channel (E12-12) and writes it to the pasteboard (via ``FakePasteboardSource``, E31-02),
/// enforcing the 1 MiB size cap and the sensitive-clip concealed/transient markers.
@Suite("PasteboardWriter", .serialized)
struct PasteboardWriterTests {
    @Test
    func pasteboardWriter_receivedText_pasteboardStringEqualsText() async throws {
        let source = FakePasteboardSource()
        let session = FakeTandemSession()
        let writer = PasteboardWriter(source: source, session: session)
        await writer.start()

        var clipboardText = Tandem_V1_ClipboardText()
        clipboardText.originTag = "android"
        clipboardText.text = "hello from phone"
        await session.inject(InboundFrame(channel: .clipboard, seq: 0, ack: 0, payload: .clipboardText(clipboardText)))

        let wrote = await waitUntilTrue { source.string(forType: .string) == "hello from phone" }
        #expect(wrote)
    }

    @Test
    func pasteboardWriter_pasteboardOwnedByOtherApp_stillWritesText() async throws {
        let source = FakePasteboardSource()
        source.ownedByOtherApp = true
        let session = FakeTandemSession()
        let writer = PasteboardWriter(source: source, session: session)
        await writer.start()

        var clipboardText = Tandem_V1_ClipboardText()
        clipboardText.originTag = "android"
        clipboardText.text = "copied on phone"
        await session.inject(InboundFrame(channel: .clipboard, seq: 0, ack: 0, payload: .clipboardText(clipboardText)))

        let wrote = await waitUntilTrue { source.string(forType: .string) == "copied on phone" }
        #expect(wrote)
    }

    @Test
    func pasteboardWriter_textOver1MiB_pasteboardUnchanged() async throws {
        let source = FakePasteboardSource()
        source.setString("unchanged", forType: .string)
        let session = FakeTandemSession()
        let writer = PasteboardWriter(source: source, session: session)
        await writer.start()

        var clipboardText = Tandem_V1_ClipboardText()
        clipboardText.originTag = "android"
        clipboardText.text = String(repeating: "a", count: PasteboardWriter.maxTextBytes + 1)
        await session.inject(InboundFrame(channel: .clipboard, seq: 0, ack: 0, payload: .clipboardText(clipboardText)))

        // Drain a same-channel, definitely-processed-after frame to know the oversized one has
        // already been handled (or dropped) before asserting.
        var sentinel = Tandem_V1_ClipboardText()
        sentinel.originTag = "android"
        sentinel.text = "sentinel"
        await session.inject(InboundFrame(channel: .clipboard, seq: 1, ack: 0, payload: .clipboardText(sentinel)))
        _ = await waitUntilTrue { source.string(forType: .string) == "sentinel" }

        #expect(source.string(forType: .string) == "sentinel", "oversized text must never have been written")
    }

    @Test
    func pasteboardWriter_sensitiveText_writtenWithConcealedAndTransientTypes() async throws {
        let source = FakePasteboardSource()
        let session = FakeTandemSession()
        let writer = PasteboardWriter(source: source, session: session)
        await writer.start()

        var clipboardText = Tandem_V1_ClipboardText()
        clipboardText.originTag = "android"
        clipboardText.text = "one-time password"
        clipboardText.sensitive = true
        await session.inject(InboundFrame(channel: .clipboard, seq: 0, ack: 0, payload: .clipboardText(clipboardText)))

        let wrote = await waitUntilTrue { source.string(forType: .string) == "one-time password" }
        #expect(wrote)
        #expect(source.string(forType: ConcealedTypeFilter.concealedType) != nil)
        #expect(source.string(forType: ConcealedTypeFilter.transientType) != nil)
    }
}
