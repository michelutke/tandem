import Foundation
import TandemProtocol

/// The single FILES-channel consumer for one session: routes every inbound frame to the transfer
/// and photo services that own it, so none of them reads the channel itself (two readers of one
/// channel would split its frames). Incoming offers go to ``AcceptFlow``; chunks are only handed to
/// ``FileReceiver`` for a transfer that ``AcceptFlow`` accepted (or one ``FileReceiver/resumeRetained()``
/// resumed), so a peer cannot push bytes for an offer the user never accepted (invariant 5).
public actor FilesChannelRouter {
    private static let maxRememberedOffers = 16

    private let acceptFlow: AcceptFlow
    private let receiver: FileReceiver
    private let transfers: SessionFileTransferService
    private let photos: SessionPhotoService
    private var offers: [String: Tandem_V1_FileOffer] = [:]
    private var offerOrder: [String] = []

    public init(
        acceptFlow: AcceptFlow,
        receiver: FileReceiver,
        transfers: SessionFileTransferService,
        photos: SessionPhotoService
    ) {
        self.acceptFlow = acceptFlow
        self.receiver = receiver
        self.transfers = transfers
        self.photos = photos
    }

    public func route(_ payload: Tandem_V1_Envelope.OneOf_Payload?) async {
        switch payload {
        case .fileOffer(let offer): await handle(offer)
        case .fileAccept(let accept): await transfers.handle(accept: accept)
        case .fileReject(let reject): await transfers.handle(reject: reject)
        case .fileChunk(let chunk): await handle(chunk)
        case .fileComplete(let complete): await handle(complete)
        case .fileCancel(let cancel): await handle(cancel)
        case .fileResumeRequest(let resume): await transfers.handle(resume: resume)
        default: await routePhoto(payload)
        }
    }

    private func routePhoto(_ payload: Tandem_V1_Envelope.OneOf_Payload?) async {
        switch payload {
        case .photoPageResult(let result): await photos.handle(result)
        case .thumbResult(let result): await photos.handle(result)
        case .photoError(let error): await photos.handle(error)
        default: break
        }
    }

    /// Fails outstanding photo requests; called once the FILES stream has finished.
    public func sessionEnded() async {
        await photos.cancelAll()
    }

    private func handle(_ offer: Tandem_V1_FileOffer) async {
        remember(offer)
        await acceptFlow.handle(offer: offer)
    }

    private func handle(_ chunk: Tandem_V1_FileChunk) async {
        guard await isReceiving(chunk.id) else { return }
        await receiver.handle(chunk: chunk)
        await releaseIfEnded(chunk.id)
    }

    private func handle(_ complete: Tandem_V1_FileComplete) async {
        await receiver.handle(complete: complete)
        await acceptFlow.transferEnded(id: complete.id)
        forget(complete.id)
    }

    private func handle(_ cancel: Tandem_V1_FileCancel) async {
        await receiver.handle(cancel: cancel)
        await transfers.handle(cancel: cancel)
        await acceptFlow.transferEnded(id: cancel.id)
        forget(cancel.id)
    }

    private func isReceiving(_ id: String) async -> Bool {
        if await receiver.hasTransfer(id: id) { return true }
        guard await acceptFlow.isActive(id: id), let offer = offers[id] else { return false }
        await receiver.begin(offer: offer)
        return await receiver.hasTransfer(id: id)
    }

    private func releaseIfEnded(_ id: String) async {
        guard await !receiver.hasTransfer(id: id) else { return }
        await acceptFlow.transferEnded(id: id)
        forget(id)
    }

    private func remember(_ offer: Tandem_V1_FileOffer) {
        if offers.updateValue(offer, forKey: offer.id) == nil {
            offerOrder.append(offer.id)
        }
        while offerOrder.count > Self.maxRememberedOffers {
            offers.removeValue(forKey: offerOrder.removeFirst())
        }
    }

    private func forget(_ id: String) {
        offers.removeValue(forKey: id)
        offerOrder.removeAll { $0 == id }
    }
}

/// Reads `session`'s FILES channel until it finishes, routing every frame through `router`. Let it
/// finish on its own rather than cancelling it (a cancelled `AsyncStream` consumer can drop an
/// already-buffered frame, see ``startNotificationPresentationReader``'s note).
public func startFilesChannelReader(
    session: any TandemSession,
    router: FilesChannelRouter
) -> Task<Void, Never> {
    Task {
        for await frame in await session.receive(.files) {
            await router.route(frame.payload)
        }
        await router.sessionEnded()
    }
}
