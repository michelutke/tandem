import FeatureFiles
import FeatureMessaging
import FeatureNotifications
import Foundation
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTransport

/// Everything E22-12 composes onto registered sessions: one ``SessionServiceHost`` attaching each
/// feature service exactly once per session (every channel read goes through
/// ``TandemSession/receive(_:)``, the one per-channel dispatch point) and detaching it when the
/// session ends. Every store with peer data is registered in `purgeRegistry`, so an unpair purges
/// all of it.
struct SessionFeatures: Sendable {
    let host: SessionServiceHost
    /// Routes ``SendEntryHandler`` and ``SendRequestAgent`` to whichever session is attached;
    /// not connected between sessions.
    let fileTransfer: ActiveFileTransferService
    private let sendRequestWake: SendRequestWakeObserver?

    static func make(purgeRegistry: PeerDataPurgeRegistry) -> SessionFeatures {
        let fileTransfer = ActiveFileTransferService()
        var services: [any SessionService] = []
        let iconCache = makeIconCache(purgeRegistry: purgeRegistry)
        let notifications = NotificationsSessionService(iconCache: iconCache)
        Task { await purgeRegistry.register(notifications.coordinator) }
        services.append(notifications)
        services.append(contentsOf: makeMessagingService(purgeRegistry: purgeRegistry))
        let filesService = makeFilesService(fileTransfer: fileTransfer, purgeRegistry: purgeRegistry)
        services.append(contentsOf: filesService.map { [$0] } ?? [])
        let agent = (try? SendRequestQueue()).map { SendRequestAgent(queue: $0, transfer: fileTransfer) }
        filesService?.agent = agent
        let wake = agent.map { agent in SendRequestWakeObserver { Task { await agent.drain() } } }
        return SessionFeatures(
            host: SessionServiceHost(services: services),
            fileTransfer: fileTransfer,
            sendRequestWake: wake
        )
    }

    /// `chaining`'s own handling plus attaching every feature service to the new session.
    func onSessionRegistered(
        chaining existing: NWListenerFactory.SessionRegisteredHandler?
    ) -> NWListenerFactory.SessionRegisteredHandler {
        let host = host
        return { peer, session in
            existing?(peer, session)
            host.sessionRegistered(peer: peer, session: session)
        }
    }

    var onSessionEnded: NWListenerFactory.SessionRegisteredHandler {
        let host = host
        return { peer, session in
            host.sessionEnded(peer: peer, session: session)
        }
    }

    private static func makeIconCache(purgeRegistry: PeerDataPurgeRegistry) -> IconCache? {
        guard let directory = cachesDirectory(named: "NotificationIcons"),
              let cache = try? IconCache(directory: directory) else { return nil }
        Task { await purgeRegistry.register(cache) }
        return cache
    }

    private static func makeMessagingService(purgeRegistry: PeerDataPurgeRegistry) -> [any SessionService] {
        guard let smsStore = try? GrdbSmsStore.openDefault(),
              let contactsStore = try? GrdbContactsStore.openDefault() else { return [] }
        Task {
            await purgeRegistry.register(smsStore)
            await purgeRegistry.register(contactsStore)
        }
        return [MessagingSessionService(smsStore: smsStore, contactsStore: contactsStore)]
    }

    private static func makeFilesService(
        fileTransfer: ActiveFileTransferService,
        purgeRegistry: PeerDataPurgeRegistry
    ) -> FilesSessionService? {
        guard let directories = try? TransferDirectories.system(),
              let thumbnailDirectory = cachesDirectory(named: "Thumbnails"),
              let thumbnails = try? ThumbnailCache(directory: thumbnailDirectory, now: { Date() }) else { return nil }
        Task {
            await purgeRegistry.register(thumbnails)
            await purgeRegistry.register(RetainedPartsPurger(staging: directories.staging))
        }
        return FilesSessionService(directories: directories, thumbnails: thumbnails, activeTransfer: fileTransfer)
    }

    private static func cachesDirectory(named name: String) -> URL? {
        try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Tandem", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}

/// Notification presentation, icon storage, dismiss sync and action replies for the attached
/// session. `UNNotificationPresenter.responses` is single-consumer, so one long-lived reader
/// routes every response to the handlers of whichever session is currently attached.
final class NotificationsSessionService: SessionService, @unchecked Sendable {
    private actor ActiveHandlers {
        private var handlers: (action: NotificationActionHandler, dismiss: NotificationDismissSync)?

        func set(_ handlers: (action: NotificationActionHandler, dismiss: NotificationDismissSync)?) {
            self.handlers = handlers
        }

        func route(_ event: NotificationResponseEvent) async {
            await handlers?.action.handle(event)
            await handlers?.dismiss.handle(event)
        }
    }

    private let presenter: UNNotificationPresenter
    let coordinator: NotificationPresentationCoordinator
    private let iconCache: IconCache?
    private let active = ActiveHandlers()
    private let screenLock = DistributedScreenLockState(notificationCenter: DistributedNotificationCenter.default())

    init(iconCache: IconCache?) {
        let presenter = UNNotificationPresenter()
        self.presenter = presenter
        self.iconCache = iconCache
        coordinator = NotificationPresentationCoordinator(
            presenter: presenter,
            iconCache: iconCache,
            screenLockState: screenLock,
            hidesContentWhenLocked: { true }
        )
        let active = active
        Task {
            for await event in presenter.responses {
                await active.route(event)
            }
        }
    }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let action = NotificationActionHandler(presenter: presenter, session: session)
        let dismiss = NotificationDismissSync(presenter: presenter, session: session)
        await active.set((action, dismiss))
        _ = startNotificationPresentationReader(
            peer: peer,
            session: session,
            coordinator: coordinator,
            iconCache: iconCache,
            actionHandler: action,
            dismissSync: dismiss
        )
    }

    func detach(peer: SpkiFingerprint) async {
        await active.set(nil)
    }
}

/// SMS and contacts sync clients over the GRDB stores. The channel readers end on their own once
/// the session's streams finish.
final class MessagingSessionService: SessionService, @unchecked Sendable {
    private let smsStore: any SmsStore
    private let contactsStore: any ContactsStore

    init(smsStore: any SmsStore, contactsStore: any ContactsStore) {
        self.smsStore = smsStore
        self.contactsStore = contactsStore
    }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let sms = SmsSyncClient(peer: peer, store: smsStore, session: session)
        let contacts = ContactsSyncClient(peer: peer, session: session, store: contactsStore)
        _ = startSmsSyncReader(session: session, client: sms)
        _ = startContactsSyncReader(session: session, client: contacts)
        Task {
            await sms.requestSync()
            try? await contacts.requestSync()
        }
    }

    func detach(peer: SpkiFingerprint) async {}
}

/// File transfer and photos for the attached session: one FILES reader (``FilesChannelRouter``),
/// the production ``SessionFileTransferService`` behind ``ActiveFileTransferService``, and a
/// drain of the Share-extension queue once connected.
final class FilesSessionService: SessionService, @unchecked Sendable {
    var agent: SendRequestAgent?
    /// The attached session's photo service behind the thumbnail cache, for the photo grid.
    private(set) var photos: (any PhotoService)?

    private let directories: TransferDirectories
    private let thumbnails: ThumbnailCache
    private let activeTransfer: ActiveFileTransferService

    init(directories: TransferDirectories, thumbnails: ThumbnailCache, activeTransfer: ActiveFileTransferService) {
        self.directories = directories
        self.thumbnails = thumbnails
        self.activeTransfer = activeTransfer
    }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let transfers = SessionFileTransferService(session: session, scheduler: FilesScheduler(session: session))
        let acceptFlow = AcceptFlow(
            session: session,
            freeSpace: VolumeFreeSpaceProvider(),
            presenter: UnansweredAcceptPrompts(),
            clock: ContinuousClock(),
            settings: AcceptSettings(),
            destination: directories.destination
        )
        let receiver = FileReceiver(
            session: session,
            directories: directories,
            sink: FileHandleSink(),
            peer: peer.bytes.map { String(format: "%02x", $0) }.joined(),
            now: { Date() }
        )
        let photoService = SessionPhotoService(session: session)
        photos = CachingPhotoService(base: photoService, cache: thumbnails, peer: peer)
        let router = FilesChannelRouter(
            acceptFlow: acceptFlow,
            receiver: receiver,
            transfers: transfers,
            photos: photoService
        )
        _ = startFilesChannelReader(session: session, router: router)
        activeTransfer.attach(transfers)
        let agent = agent
        Task {
            await receiver.resumeRetained()
            await agent?.drain()
        }
    }

    func detach(peer: SpkiFingerprint) async {
        activeTransfer.detach()
    }
}

/// Accept prompts are not presented anywhere yet, so an offer that is neither auto-accepted nor
/// rejected outright is rejected `TIMEOUT` by ``AcceptFlow`` after its prompt window; nothing is
/// ever accepted without the user.
private struct UnansweredAcceptPrompts: AcceptPromptPresenter {
    let responses = AsyncStream<AcceptPromptResponse> { $0.finish() }

    func present(offerId: String, displayName: String, size: UInt64) async {}
    func remove(offerId: String) async {}
}
