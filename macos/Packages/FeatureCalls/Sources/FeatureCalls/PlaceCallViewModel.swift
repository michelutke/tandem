import Foundation
import Observation
import TandemProtocol
import TandemStore

public struct PlaceCallSim: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let name: String

    public init(id: Int32, name: String) {
        self.id = id
        self.name = name
    }
}

/// Where the dial flow learns the phone's SIMs (latest `SimList`, E50-05).
public protocol PlaceCallSimSource: Sendable {
    func sims() async -> [PlaceCallSim]
}

/// Place-call flow (E52-07, PRD F-8.4, UC-21). With two or more SIMs the user picks a subscription
/// first; with one the `PlaceCallRequest` goes out immediately with `subscription_id` 0. The
/// phone's `CallActionResult` moves the state to `.needsPhoneTap` or `.failed`. Numbers are never
/// logged (invariant 7).
@MainActor
@Observable
public final class PlaceCallViewModel {
    public enum State: Equatable {
        case idle
        case choosingSim([PlaceCallSim])
        case dialing
        case needsPhoneTap
        case failed(Tandem_V1_CallActionErrorCode)
    }

    public private(set) var state: State = .idle

    /// The line to show for the dialing, tap-on-phone and failed states; `nil` otherwise.
    public var statusMessage: String? {
        switch state {
        case .idle, .choosingSim: nil
        case .dialing: "Calling."
        case .needsPhoneTap: "Tap the notification on your phone to start the call."
        case .failed(.invalidNumber): "Can't call that from your Mac. Call emergency numbers from your phone."
        case .failed: "Couldn't call."
        }
    }

    @ObservationIgnored private let session: any TandemSession
    @ObservationIgnored private let simSource: any PlaceCallSimSource
    @ObservationIgnored private let makeRequestId: @Sendable () -> String
    @ObservationIgnored private let numberNormalizer: PhoneNumberNormalizer
    @ObservationIgnored private var pendingAddress = ""
    @ObservationIgnored private var pendingRequestId: String?
    @ObservationIgnored private nonisolated(unsafe) var resultTask: Task<Void, Never>?

    public init(
        session: any TandemSession,
        simSource: any PlaceCallSimSource,
        makeRequestId: @escaping @Sendable () -> String = { UUID().uuidString },
        numberNormalizer: PhoneNumberNormalizer = PhoneNumberNormalizer()
    ) {
        self.session = session
        self.simSource = simSource
        self.makeRequestId = makeRequestId
        self.numberNormalizer = numberNormalizer
    }

    deinit {
        resultTask?.cancel()
    }

    /// Starts observing `CallActionResult`s on the CALLS channel.
    public func start() {
        resultTask?.cancel()
        let session = session
        resultTask = Task { [weak self] in
            for await frame in await session.receive(.calls) {
                guard case .callActionResult(let result)? = frame.payload else { continue }
                await self?.handle(result)
            }
        }
    }

    public func place(number: String) async {
        pendingAddress = numberNormalizer.lookupKey(for: number)
        let sims = await simSource.sims()
        if sims.count >= 2 {
            state = .choosingSim(sims)
        } else {
            await send(subscriptionId: 0)
        }
    }

    public func choose(subscriptionId: Int32) async {
        guard case .choosingSim = state else { return }
        await send(subscriptionId: subscriptionId)
    }

    public func handle(_ result: Tandem_V1_CallActionResult) {
        guard result.requestID == pendingRequestId else { return }
        if result.success { return }
        state = result.errorCode == .needsPhoneTap ? .needsPhoneTap : .failed(result.errorCode)
    }

    private func send(subscriptionId: Int32) async {
        var request = Tandem_V1_PlaceCallRequest()
        request.requestID = makeRequestId()
        request.address = pendingAddress
        request.subscriptionID = subscriptionId
        pendingRequestId = request.requestID
        state = .dialing
        do {
            try await session.send(.calls, payload: .placeCallRequest(request))
        } catch {
            state = .failed(.unspecified)
        }
    }
}
