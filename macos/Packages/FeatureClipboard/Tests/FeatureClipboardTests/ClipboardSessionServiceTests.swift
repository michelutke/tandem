import AppKit
import Foundation
import Testing
@testable import FeatureClipboard
@testable import TandemCrypto
@testable import TandemProtocol
@testable import TandemTestSupport

private final class SessionFrameSource: FrameSource, @unchecked Sendable {
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator
    private var buffer = Data()

    init(_ end: InMemoryConnectionPair.End) {
        iterator = end.receive().makeAsyncIterator()
    }

    func read(exactly count: Int) async throws -> Data {
        while buffer.count < count {
            guard let chunk = try await iterator.next() else {
                let collected = buffer
                buffer.removeAll()
                return collected
            }
            buffer.append(chunk)
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }
}

private actor ReceivedTexts {
    private(set) var texts: [String] = []

    func record(_ text: String) {
        texts.append(text)
    }
}

private actor EventFlag {
    private(set) var received = false

    func markReceived() {
        received = true
    }
}

/// Manual-test regression: the Mac's clipboard path end to end on the real composition pieces
/// (``ClipboardSessionService`` + ``ActiveClipboard`` over a real ``ByteStreamSession`` on an
/// in-memory connection), against a bare peer multiplexer standing in for the phone.
@Suite("Clipboard session service", .serialized)
struct ClipboardSessionServiceTests {
    // swiftlint:disable:next force_try
    private let peerFingerprint = try! SpkiFingerprint(bytes: Data(repeating: 7, count: 32))

    private struct Rig {
        let service: ClipboardSessionService
        let active: ActiveClipboard
        let source: FakePasteboardSource
        let session: ByteStreamSession
        let peer: ChannelMultiplexer
    }

    private func makeRig() async -> Rig {
        let clock = ManualTestClock()
        let pair = InMemoryConnectionPair()
        let multiplexer = ChannelMultiplexer(source: SessionFrameSource(pair.endA), sink: pair.endA.send)
        let session = ByteStreamSession(multiplexer: multiplexer, stateMachine: ConnectionStateMachine(clock: clock))
        await multiplexer.start()
        let peer = ChannelMultiplexer(source: SessionFrameSource(pair.endB), sink: pair.endB.send)
        await peer.start()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let active = ActiveClipboard()
        let service = ClipboardSessionService(source: source, clock: clock, active: active)
        return Rig(service: service, active: active, source: source, session: session, peer: peer)
    }

    @Test
    func clipboardSessionService_phoneSendsClip_writesPasteboardAndReportsReceived() async throws {
        let rig = await makeRig()
        await rig.service.attach(peer: peerFingerprint, session: rig.session)
        let flag = EventFlag()
        let events = Task {
            for await event in rig.active.events where event == .received {
                await flag.markReceived()
            }
        }

        var clip = Tandem_V1_ClipboardText()
        clip.originTag = "android"
        clip.text = "from the phone"
        try await rig.peer.send(.clipboard, payload: .clipboardText(clip))

        #expect(await waitUntilTrue { rig.source.string(forType: .string) == "from the phone" })
        #expect(await waitUntilTrue { await flag.received })
        events.cancel()
        await rig.service.detach(peer: peerFingerprint)
    }

    @Test
    func clipboardSessionService_pushCurrentItem_phoneReceivesClipboardText() async throws {
        let rig = await makeRig()
        await rig.service.attach(peer: peerFingerprint, session: rig.session)
        let received = ReceivedTexts()
        let collect = Task {
            for await frame in await rig.peer.inbound(.clipboard) {
                guard case .clipboardText(let clip) = frame.payload else { continue }
                await received.record(clip.text)
            }
        }
        rig.source.setString("to the phone", forType: .string)

        #expect(await rig.active.pushCurrentItem() == .sent)

        #expect(await waitUntilTrue { await received.texts == ["to the phone"] })
        collect.cancel()
        await rig.service.detach(peer: peerFingerprint)
    }

    @Test
    func clipboardSessionService_detached_pushCurrentItemIsNotConnected() async {
        let rig = await makeRig()
        await rig.service.attach(peer: peerFingerprint, session: rig.session)
        #expect(rig.active.isConnected)

        await rig.service.detach(peer: peerFingerprint)

        #expect(!rig.active.isConnected)
        #expect(await rig.active.pushCurrentItem() == nil)
    }
}
