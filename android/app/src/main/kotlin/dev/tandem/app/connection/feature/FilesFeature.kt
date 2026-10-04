package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.PeerDataPurging
import dev.tandem.core.transport.TandemSession
import dev.tandem.feature.files.AcceptFlow
import dev.tandem.feature.files.AcceptSettings
import dev.tandem.feature.files.DownloadsPublisher
import dev.tandem.feature.files.FileReceiver
import dev.tandem.feature.files.FileSender
import dev.tandem.feature.files.FilesScheduler
import dev.tandem.feature.files.FreeSpaceProvider
import dev.tandem.feature.files.MediaPermissionChecker
import dev.tandem.feature.files.MediaStoreSource
import dev.tandem.feature.files.OriginalOutcome
import dev.tandem.feature.files.OriginalResponder
import dev.tandem.feature.files.PhotoPageOutcome
import dev.tandem.feature.files.PhotoPageResponder
import dev.tandem.feature.files.PhotoPager
import dev.tandem.feature.files.ReceivedFileNotifier
import dev.tandem.feature.files.SourceFileReader
import dev.tandem.feature.files.ThumbOutcome
import dev.tandem.feature.files.ThumbnailLoader
import dev.tandem.feature.files.ThumbnailResponder
import dev.tandem.feature.files.TransferPrompter
import dev.tandem.feature.files.TransferStore
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.PhotoError
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Clock

/**
 * Attaches the FILES channel consumers to a session (F-7.x): receiver, accept flow, sender, and the
 * photo-browsing responders. Their protocol state needs a single-threaded dispatcher, so
 * [serialDispatcher] hands each collaborator its own. [purger] stays registered across sessions and
 * clears the live receiver's state (or just the part-file store) when a peer's data is purged.
 */
@Suppress("LongParameterList") // one seam per FILES collaborator
class FilesFeature(
    private val store: TransferStore,
    private val publisher: DownloadsPublisher,
    private val notifier: ReceivedFileNotifier,
    private val prompter: TransferPrompter,
    private val freeSpace: FreeSpaceProvider,
    private val reader: SourceFileReader,
    private val mediaSource: MediaStoreSource,
    private val thumbnailLoader: ThumbnailLoader,
    private val permissionChecker: MediaPermissionChecker,
    private val acceptSettings: () -> AcceptSettings,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher,
    private val serialDispatcher: () -> CoroutineDispatcher,
) : SessionFeature {
    @Volatile
    private var receiver: FileReceiver? = null

    val purger: PeerDataPurging =
        PeerDataPurging { peerFingerprint ->
            receiver?.purgeAll(peerFingerprint) ?: withContext(ioDispatcher) { store.deleteAll() }
        }

    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
    ) {
        val fileReceiver =
            FileReceiver(session, store, publisher, notifier, peer, clock, ioDispatcher, serialDispatcher())
        val acceptFlow =
            AcceptFlow(session, freeSpace, prompter, acceptSettings, { fileReceiver.activeCount }, serialDispatcher())
        acceptFlow.onAccepted = fileReceiver::expect
        val scheduler = FilesScheduler(session, serialDispatcher())
        val sender = FileSender(session, scheduler, reader, ioDispatcher, serialDispatcher())
        receiver = fileReceiver
        try {
            routePhotoRequests(session, OriginalResponder(mediaSource, sender))
        } finally {
            receiver = null
            acceptFlow.close()
            sender.close()
            scheduler.close()
            fileReceiver.close()
        }
    }

    private suspend fun routePhotoRequests(
        session: TandemSession,
        original: OriginalResponder,
    ) {
        val thumbnails = ThumbnailResponder(thumbnailLoader, ioDispatcher)
        val pages = PhotoPageResponder(permissionChecker, PhotoPager(mediaSource))
        coroutineScope {
            session.receive(Channel.CHANNEL_FILES).collect { envelope ->
                when {
                    envelope.hasPhotoPage() -> {
                        launch { replyPage(session, withContext(ioDispatcher) { pages.respond(envelope.photoPage) }) }
                    }

                    envelope.hasThumbRequest() -> {
                        launch { replyThumb(session, thumbnails.respond(envelope.thumbRequest)) }
                    }

                    envelope.hasOriginalRequest() -> {
                        launch {
                            val outcome = withContext(ioDispatcher) { original.respond(envelope.originalRequest) }
                            replyOriginal(session, outcome)
                        }
                    }
                }
            }
        }
    }

    private suspend fun replyPage(
        session: TandemSession,
        outcome: PhotoPageOutcome,
    ) {
        when (outcome) {
            is PhotoPageOutcome.Page -> session.send(Channel.CHANNEL_FILES) { photoPageResult = outcome.result }
            is PhotoPageOutcome.Failure -> sendError(session, outcome.error)
        }
    }

    private suspend fun replyThumb(
        session: TandemSession,
        outcome: ThumbOutcome,
    ) {
        when (outcome) {
            is ThumbOutcome.Thumb -> session.send(Channel.CHANNEL_FILES) { thumbResult = outcome.result }
            is ThumbOutcome.Failure -> sendError(session, outcome.error)
        }
    }

    private suspend fun replyOriginal(
        session: TandemSession,
        outcome: OriginalOutcome,
    ) {
        if (outcome is OriginalOutcome.Failure) sendError(session, outcome.error)
    }

    private suspend fun sendError(
        session: TandemSession,
        error: PhotoError,
    ) {
        session.send(Channel.CHANNEL_FILES) { photoError = error }
    }
}
