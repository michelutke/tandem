import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private let mebibyte: UInt64 = 1 << 20
private let gibibyte: UInt64 = 1 << 30

private struct StubFreeSpaceProvider: FreeSpaceProvider {
    let available: UInt64
    func availableBytes(at destination: URL) -> UInt64 { available }
}

private actor RecordingPromptPresenter: AcceptPromptPresenter {
    struct Prompt: Equatable { let offerId: String; let displayName: String; let size: UInt64 }
    private(set) var prompts: [Prompt] = []
    private(set) var removed: [String] = []
    nonisolated let responses: AsyncStream<AcceptPromptResponse>

    init() { responses = AsyncStream { _ in } }

    func present(offerId: String, displayName: String, size: UInt64) {
        prompts.append(Prompt(offerId: offerId, displayName: displayName, size: size))
    }

    func remove(offerId: String) { removed.append(offerId) }
}

private struct Harness {
    let session = FakeTandemSession()
    let presenter = RecordingPromptPresenter()
    let space: StubFreeSpaceProvider
    let clock = ManualTestClock()
    let flow: AcceptFlow

    init(available: UInt64 = 100 * gibibyte, autoAccept: Bool = false) {
        space = StubFreeSpaceProvider(available: available)
        flow = AcceptFlow(
            session: session,
            freeSpace: space,
            presenter: presenter,
            clock: clock,
            settings: AcceptSettings(autoAcceptEnabled: autoAccept),
            destination: URL(fileURLWithPath: "/tmp")
        )
    }

    func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    func sentPayloads() async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await session.sent.map(\.payload)
    }
}

private func offer(id: String = "t1", name: String = "a.txt", size: UInt64 = 1000) -> Tandem_V1_FileOffer {
    var offer = Tandem_V1_FileOffer()
    offer.id = id
    offer.name = name
    offer.size = size
    return offer
}

private func reject(_ id: String, _ reason: Tandem_V1_TransferReason) -> Tandem_V1_Envelope.OneOf_Payload {
    var message = Tandem_V1_FileReject()
    message.id = id
    message.reason = reason
    return .fileReject(message)
}

private func accept(_ id: String) -> Tandem_V1_Envelope.OneOf_Payload {
    var message = Tandem_V1_FileAccept()
    message.id = id
    return .fileAccept(message)
}

@Suite struct AcceptFlowTests {
    @Test func macosAcceptFlow_freeSpaceBelowSizePlusReserve_insufficientSpaceRejectNoPrompt() async {
        let harness = Harness(available: 1000 + 64 * mebibyte - 1)
        await harness.flow.handle(offer: offer(size: 1000))
        #expect(await harness.sentPayloads() == [reject("t1", .insufficientSpace)])
        #expect(await harness.presenter.prompts.isEmpty)
    }

    @Test func macosAcceptFlow_autoAcceptOn_fileAcceptSentWithoutPrompt() async {
        let harness = Harness(autoAccept: true)
        await harness.flow.handle(offer: offer())
        #expect(await harness.sentPayloads() == [accept("t1")])
        #expect(await harness.presenter.prompts.isEmpty)
    }

    @Test func macosAcceptFlow_declineAction_fileRejectDeclinedSent() async {
        let harness = Harness()
        await harness.flow.handle(offer: offer())
        #expect(await harness.presenter.prompts.count == 1)
        await harness.flow.handle(response: AcceptPromptResponse(offerId: "t1", decision: .decline))
        #expect(await harness.sentPayloads() == [reject("t1", .declined)])
        #expect(await harness.presenter.removed == ["t1"])
    }

    @Test func macosAcceptFlow_acceptAction_fileAcceptSent() async {
        let harness = Harness()
        await harness.flow.handle(offer: offer())
        await harness.flow.handle(response: AcceptPromptResponse(offerId: "t1", decision: .accept))
        #expect(await harness.sentPayloads() == [accept("t1")])
    }

    @Test func macosAcceptFlow_noAnswerFor300s_timeoutRejectAndPromptRemoved() async {
        let harness = Harness()
        await harness.flow.handle(offer: offer())
        await harness.settle()
        harness.clock.advance(by: .seconds(299))
        await harness.settle()
        #expect(await harness.sentPayloads().isEmpty)
        harness.clock.advance(by: .seconds(1))
        await harness.settle()
        #expect(await harness.sentPayloads() == [reject("t1", .timeout)])
        #expect(await harness.presenter.removed == ["t1"])
    }

    @Test func macosAcceptFlow_answeredBeforeTimeout_noTimeoutReject() async {
        let harness = Harness()
        await harness.flow.handle(offer: offer())
        await harness.settle()
        await harness.flow.handle(response: AcceptPromptResponse(offerId: "t1", decision: .accept))
        harness.clock.advance(by: .seconds(400))
        await harness.settle()
        #expect(await harness.sentPayloads() == [accept("t1")])
    }

    @Test func macosAcceptFlow_autoAcceptOnOfferOver1GiB_promptShown() async {
        let harness = Harness(autoAccept: true)
        await harness.flow.handle(offer: offer(size: gibibyte + 1))
        #expect(await harness.sentPayloads().isEmpty)
        #expect(await harness.presenter.prompts.count == 1)
    }

    @Test func macosAcceptFlow_fifthPendingOffer_busyRejectNoPrompt() async {
        let harness = Harness()
        for index in 1...5 {
            await harness.flow.handle(offer: offer(id: "t\(index)"))
        }
        #expect(await harness.sentPayloads() == [reject("t5", .busy)])
        #expect(await harness.presenter.prompts.count == 4)
    }

    @Test func macosAcceptFlow_offerWhileTwoTransfersActive_busyRejectNoPrompt() async {
        let harness = Harness(autoAccept: true)
        await harness.flow.handle(offer: offer(id: "t1"))
        await harness.flow.handle(offer: offer(id: "t2"))
        await harness.flow.handle(offer: offer(id: "t3"))
        #expect(await harness.sentPayloads() == [accept("t1"), accept("t2"), reject("t3", .busy)])
        await harness.flow.transferEnded(id: "t1")
        await harness.flow.handle(offer: offer(id: "t4"))
        #expect(await harness.sentPayloads().last == accept("t4"))
    }

    @Test func macosAcceptFlow_offerOver64GiB_tooLargeReject() async {
        let harness = Harness()
        await harness.flow.handle(offer: offer(size: (64 * gibibyte) + 1))
        #expect(await harness.sentPayloads() == [reject("t1", .tooLarge)])
        #expect(await harness.presenter.prompts.isEmpty)
    }

    @Test func macosAcceptFlow_nameOver1024Bytes_invalidNameReject() async {
        let harness = Harness()
        await harness.flow.handle(offer: offer(name: String(repeating: "a", count: 1025)))
        #expect(await harness.sentPayloads() == [reject("t1", .invalidName)])
    }

    @Test func macosAcceptFlow_promptShowsSanitizedName() async {
        let harness = Harness()
        await harness.flow.handle(offer: offer(name: "re\u{202E}port\u{0007}.txt"))
        #expect(await harness.presenter.prompts.first?.displayName == "report.txt")
    }

    @Test func originalDownload_offerMatchesPendingTransferId_acceptedWithoutPrompt() async {
        let harness = Harness()
        await harness.flow.expectOriginal(transferId: "t1")
        await harness.flow.handle(offer: offer(id: "t1"))
        #expect(await harness.sentPayloads() == [accept("t1")])
        #expect(await harness.presenter.prompts.isEmpty)
    }

    @Test func originalDownload_unsolicitedOffer_stillPrompts() async {
        let harness = Harness()
        await harness.flow.expectOriginal(transferId: "other")
        await harness.flow.handle(offer: offer(id: "t1"))
        #expect(await harness.sentPayloads().isEmpty)
        #expect(await harness.presenter.prompts.count == 1)
    }

    @Test func originalDownload_matchingOfferLowSpace_stillRejectedInsufficientSpace() async {
        let harness = Harness(available: 0)
        await harness.flow.expectOriginal(transferId: "t1")
        await harness.flow.handle(offer: offer(id: "t1"))
        #expect(await harness.sentPayloads() == [reject("t1", .insufficientSpace)])
    }
}
