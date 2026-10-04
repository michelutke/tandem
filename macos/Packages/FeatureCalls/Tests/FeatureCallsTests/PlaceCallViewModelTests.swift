import FeatureCalls
import Foundation
import TandemStore
import Testing
@testable import TandemProtocol

@MainActor
@Suite struct PlaceCallViewModelTests {
    private struct FakeSimSource: PlaceCallSimSource {
        let sims: [PlaceCallSim]
        func sims() async -> [PlaceCallSim] { sims }
    }

    @MainActor private struct Harness {
        let session = FakeTandemSession()
        let viewModel: PlaceCallViewModel

        init(sims: [PlaceCallSim]) {
            viewModel = PlaceCallViewModel(
                session: session,
                simSource: FakeSimSource(sims: sims),
                makeRequestId: { "req-1" },
                numberNormalizer: PhoneNumberNormalizer(defaultRegion: "CH")
            )
        }

        func sentRequests() async -> [Tandem_V1_PlaceCallRequest] {
            await session.sent.compactMap { frame in
                guard frame.channel == .calls, case .placeCallRequest(let request) = frame.payload else { return nil }
                return request
            }
        }

        func result(_ code: Tandem_V1_CallActionErrorCode, success: Bool = false) -> Tandem_V1_CallActionResult {
            var result = Tandem_V1_CallActionResult()
            result.requestID = "req-1"
            result.success = success
            result.errorCode = code
            return result
        }
    }

    private static let twoSims = [PlaceCallSim(id: 1, name: "Work"), PlaceCallSim(id: 2, name: "Private")]

    @Test func placeCallViewModel_twoSims_promptsSubscriptionPicker() async {
        let harness = Harness(sims: Self.twoSims)

        await harness.viewModel.place(number: "079 123 45 67")

        #expect(harness.viewModel.state == .choosingSim(Self.twoSims))
        #expect(await harness.sentRequests().isEmpty)

        await harness.viewModel.choose(subscriptionId: 2)

        let requests = await harness.sentRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.subscriptionID == 2)
        #expect(requests.first?.address == "+41791234567")
        #expect(harness.viewModel.state == .dialing)
    }

    @Test func placeCallViewModel_singleSim_sendsWithoutSubscriptionId() async {
        let harness = Harness(sims: [PlaceCallSim(id: 7, name: "Only")])

        await harness.viewModel.place(number: "+41 79 123 45 67")

        let requests = await harness.sentRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.subscriptionID == 0)
        #expect(requests.first?.address == "+41791234567")
        #expect(requests.first?.requestID == "req-1")
        #expect(harness.viewModel.state == .dialing)
    }

    @Test func placeCallViewModel_needsPhoneTapResult_stateNeedsPhoneTap() async {
        let harness = Harness(sims: [])
        await harness.viewModel.place(number: "+41791234567")

        harness.viewModel.handle(harness.result(.needsPhoneTap))

        #expect(harness.viewModel.state == .needsPhoneTap)
    }

    @Test func placeCallViewModel_permissionDeniedResult_stateFailed() async {
        let harness = Harness(sims: [])
        await harness.viewModel.place(number: "+41791234567")

        harness.viewModel.handle(harness.result(.permissionDenied))

        #expect(harness.viewModel.state == .failed(.permissionDenied))
    }

    @Test func placeCallViewModel_resultForOtherRequest_ignored() async {
        let harness = Harness(sims: [])
        await harness.viewModel.place(number: "+41791234567")
        var other = harness.result(.permissionDenied)
        other.requestID = "req-other"

        harness.viewModel.handle(other)

        #expect(harness.viewModel.state == .dialing)
    }
}
