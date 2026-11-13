import AppKit
import Foundation
import Testing
@testable import FeatureClipboard
@testable import TandemProtocol
@testable import TandemTestSupport

private struct SendFailure: Error {}

private actor FailingSession: TandemSession {
    private let inner = FakeTandemSession()

    nonisolated var state: AsyncStream<ConnectionStateMachine.ConnectionState> { inner.state }

    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        throw SendFailure()
    }

    func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream {
        await inner.receive(channel)
    }

    func close() async { await inner.close() }
}

@Suite("ClipboardSenderSendFailure")
struct ClipboardSenderSendFailureTests {
    @Test
    func clipboardSender_pushWhenSendThrows_returnsNotSentDisconnected() async {
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        source.setString("hello", forType: .string)
        let sender = ClipboardSender(source: source, clock: ManualTestClock(), session: FailingSession())

        let result = await sender.pushCurrentItem()

        #expect(result == .notSentDisconnected)
    }
}
