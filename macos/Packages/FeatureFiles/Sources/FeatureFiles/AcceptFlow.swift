import Foundation
import TandemProtocol

/// Receiver-side decision for an incoming `FileOffer` (docs/protocol/SPEC.md #files-channel
/// "Cycle 4 caps"): rejects over-cap, busy and low-space offers without prompting, auto-accepts
/// small offers when enabled, otherwise prompts and rejects TIMEOUT after 300 s unanswered.
public actor AcceptFlow: OriginalOfferExpecting {
    private static let maxNameBytes = 1024
    private static let maxMimeBytes = 255
    private static let maxSize: UInt64 = 1 << 36
    private static let spaceReserve: UInt64 = 64 << 20
    private static let maxPendingOffers = 4
    private static let maxActiveTransfers = 2
    private static let promptTimeout: Duration = .seconds(300)

    private let session: any TandemSession
    private let freeSpace: any FreeSpaceProvider
    private let presenter: any AcceptPromptPresenter
    private let clock: any Clock<Duration>
    private let settings: AcceptSettings
    private let destination: URL

    private var pending: [String: Task<Void, Never>] = [:]
    private var active: Set<String> = []
    private var expectedOriginals: Set<String> = []

    public init(
        session: any TandemSession,
        freeSpace: any FreeSpaceProvider,
        presenter: any AcceptPromptPresenter,
        clock: any Clock<Duration>,
        settings: AcceptSettings,
        destination: URL
    ) {
        self.session = session
        self.freeSpace = freeSpace
        self.presenter = presenter
        self.clock = clock
        self.settings = settings
        self.destination = destination
    }

    /// Applies prompt responses from the presenter until its stream finishes.
    public func run() async {
        for await response in presenter.responses {
            await handle(response: response)
        }
    }

    public func handle(offer: Tandem_V1_FileOffer) async {
        if let reason = rejectionReason(for: offer) {
            await sendReject(offer.id, reason)
            return
        }
        if expectedOriginals.remove(offer.id) != nil {
            await sendAccept(offer.id)
            return
        }
        if settings.autoAcceptEnabled && offer.size <= settings.autoAcceptMaxSize {
            await sendAccept(offer.id)
            return
        }
        await presentPrompt(for: offer)
    }

    public func handle(response: AcceptPromptResponse) async {
        guard let timer = pending.removeValue(forKey: response.offerId) else { return }
        timer.cancel()
        await presenter.remove(offerId: response.offerId)
        switch response.decision {
        case .accept:
            await sendAccept(response.offerId)
        case .decline:
            await sendReject(response.offerId, .declined)
        }
    }

    public func expectOriginal(transferId: String) {
        expectedOriginals.insert(transferId)
    }

    public func forgetOriginal(transferId: String) {
        expectedOriginals.remove(transferId)
    }

    /// Whether `id` was accepted and its transfer has not ended yet.
    public func isActive(id: String) -> Bool {
        active.contains(id)
    }

    /// Frees the active-transfer slot taken by an accepted offer once its transfer finishes.
    public func transferEnded(id: String) {
        active.remove(id)
    }

    private func rejectionReason(for offer: Tandem_V1_FileOffer) -> Tandem_V1_TransferReason? {
        if offer.name.utf8.count > Self.maxNameBytes || offer.mime.utf8.count > Self.maxMimeBytes {
            return .invalidName
        }
        if offer.size > Self.maxSize {
            return .tooLarge
        }
        if pending.count >= Self.maxPendingOffers || active.count >= Self.maxActiveTransfers {
            return .busy
        }
        if freeSpace.availableBytes(at: destination) < offer.size + Self.spaceReserve {
            return .insufficientSpace
        }
        return nil
    }

    private func presentPrompt(for offer: Tandem_V1_FileOffer) async {
        let id = offer.id
        let clock = clock
        pending[id] = Task { [weak self] in
            guard (try? await clock.sleep(for: Self.promptTimeout)) != nil else { return }
            await self?.expire(id)
        }
        let displayName = DisplayStringSanitizer.sanitize(Data(offer.name.utf8), kind: .name)
        await presenter.present(offerId: id, displayName: displayName, size: offer.size)
    }

    private func expire(_ id: String) async {
        guard pending.removeValue(forKey: id) != nil else { return }
        await presenter.remove(offerId: id)
        await sendReject(id, .timeout)
    }

    private func sendAccept(_ id: String) async {
        active.insert(id)
        var message = Tandem_V1_FileAccept()
        message.id = id
        try? await session.send(.files, payload: .fileAccept(message))
    }

    private func sendReject(_ id: String, _ reason: Tandem_V1_TransferReason) async {
        var message = Tandem_V1_FileReject()
        message.id = id
        message.reason = reason
        try? await session.send(.files, payload: .fileReject(message))
    }
}
