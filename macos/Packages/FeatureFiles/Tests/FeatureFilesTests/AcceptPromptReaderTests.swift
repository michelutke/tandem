import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private final class ScriptedPromptPresenter: AcceptPromptPresenter, @unchecked Sendable {
    let responses: AsyncStream<AcceptPromptResponse>
    private let continuation: AsyncStream<AcceptPromptResponse>.Continuation

    init() {
        (responses, continuation) = AsyncStream<AcceptPromptResponse>.makeStream()
    }

    func answer(_ response: AcceptPromptResponse) { continuation.yield(response) }
    func present(offerId: String, displayName: String, size: UInt64) async {}
    func remove(offerId: String) async {}
}

private struct RoomyFreeSpace: FreeSpaceProvider {
    func availableBytes(at destination: URL) -> UInt64 { 100 << 30 }
}

@Suite struct AcceptPromptReaderTests {
    @Test func appComposition_incomingOffer_promptAcceptStartsTransfer() async {
        let session = FakeTandemSession()
        let presenter = ScriptedPromptPresenter()
        let flow = AcceptFlow(
            session: session,
            freeSpace: RoomyFreeSpace(),
            presenter: presenter,
            clock: ManualTestClock(),
            settings: AcceptSettings(),
            destination: URL(fileURLWithPath: "/tmp")
        )
        let reader = startAcceptPromptReader(flow: flow)
        var offer = Tandem_V1_FileOffer()
        offer.id = "t1"
        offer.name = "a.txt"
        offer.size = 1000
        await flow.handle(offer: offer)

        presenter.answer(AcceptPromptResponse(offerId: "t1", decision: .accept))
        for _ in 0..<200 { await Task.yield() }

        var accept = Tandem_V1_FileAccept()
        accept.id = "t1"
        #expect(await session.sent.map(\.payload) == [.fileAccept(accept)])
        #expect(await flow.isActive(id: "t1"))
        reader.cancel()
    }
}
