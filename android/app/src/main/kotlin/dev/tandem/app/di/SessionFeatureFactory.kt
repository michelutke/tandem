package dev.tandem.app.di

import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import android.util.Log
import android.widget.Toast
import dev.tandem.app.R
import dev.tandem.app.TandemApplication
import dev.tandem.app.activity.ActivityEventType
import dev.tandem.app.activity.ActivityRecorder
import dev.tandem.app.calls.TelephonyRegionSource
import dev.tandem.app.clipboard.ClipboardWriter
import dev.tandem.app.connection.GatedSessionFeature
import dev.tandem.app.connection.SessionFeature
import dev.tandem.app.connection.feature.CallsFeature
import dev.tandem.app.connection.feature.ClipboardFeature
import dev.tandem.app.connection.feature.ContactsFeature
import dev.tandem.app.connection.feature.FilesFeature
import dev.tandem.app.connection.feature.FocusFeature
import dev.tandem.app.connection.feature.NotificationInteractionsFeature
import dev.tandem.app.connection.feature.NotificationsFeature
import dev.tandem.app.connection.feature.RingFeature
import dev.tandem.app.connection.feature.RotationFeature
import dev.tandem.app.connection.feature.SmsFeatures
import dev.tandem.app.connection.feature.StatusFeature
import dev.tandem.app.mirror.AndroidMirrorPlatform
import dev.tandem.app.mirror.LogInputDropLog
import dev.tandem.app.mirror.MirrorConsentActivity
import dev.tandem.app.mirror.MirrorFeature
import dev.tandem.app.ring.SystemAlarmPlayer
import dev.tandem.app.ring.SystemNotificationPolicyAccess
import dev.tandem.app.settings.FeatureToggles
import dev.tandem.app.settings.SyncFeature
import dev.tandem.core.pairing.PeerDataPurgeRegistry
import dev.tandem.core.storage.rotation.RotationEventLog
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.core.storage.settings.createSettingsDataStore
import dev.tandem.core.storage.trust.TrustStore
import dev.tandem.core.transport.media.PinnedTlsMediaStreamFactory
import dev.tandem.core.transport.time.SystemElapsedRealtimeSource
import dev.tandem.feature.calls.ContextCallPermissions
import dev.tandem.feature.calls.NotificationTapToCallNotifier
import dev.tandem.feature.calls.SubscriptionManagerCallSubscriptions
import dev.tandem.feature.calls.TelecomCallGateway
import dev.tandem.feature.calls.TelephonyEmergencyNumbers
import dev.tandem.feature.clipboard.LiveClipboardSession
import dev.tandem.feature.contacts.ContentResolverContactsSource
import dev.tandem.feature.contacts.PhoneNormalizer
import dev.tandem.feature.files.AcceptSettings
import dev.tandem.feature.files.ContentResolverMediaStoreSource
import dev.tandem.feature.files.ContentResolverSourceFileReader
import dev.tandem.feature.files.ContentResolverThumbnailLoader
import dev.tandem.feature.files.FileTransferStore
import dev.tandem.feature.files.MediaPermissionChecker
import dev.tandem.feature.files.MediaStoreDownloadsPublisher
import dev.tandem.feature.files.NotificationReceivedFileNotifier
import dev.tandem.feature.files.NotificationTransferPrompter
import dev.tandem.feature.files.ReceivedFileNotifier
import dev.tandem.feature.files.StatFsFreeSpaceProvider
import dev.tandem.feature.input.LiveRemoteInput
import dev.tandem.feature.messaging.ContentResolverSmsSource
import dev.tandem.feature.messaging.ContextSendSmsPermission
import dev.tandem.feature.messaging.SmsManagerSender
import dev.tandem.feature.messaging.SubscriptionManagerSource
import dev.tandem.feature.mirror.NotificationMirrorPromptPresenter
import dev.tandem.feature.notifications.SystemInterruptionFilterGateway
import dev.tandem.feature.status.BatteryReceiverStatusSource
import dev.tandem.feature.status.ConnectivityManagerNetworkTypeSource
import dev.tandem.feature.status.StatusAggregator
import dev.tandem.feature.status.TelephonyNetworkSignalStrengthSource
import java.io.File
import java.security.SecureRandom
import java.time.Clock
import javax.net.ssl.X509KeyManager

/**
 * The per-session consumers the connection orchestrator attaches to every Ready session (E20-23,
 * E20-24). Each reads its channel through `session.receive` (the per-session dispatcher), so there is
 * one subscriber per consumer and none competes for frames.
 */
object SessionFeatureFactory {
    @Suppress("LongParameterList") // one seam per process-wide collaborator
    fun create(
        context: Context,
        clock: Clock,
        trustStore: TrustStore,
        purgeRegistry: PeerDataPurgeRegistry,
        keyManager: X509KeyManager,
        rotation: RotationComposition,
    ): List<SessionFeature> {
        val application = context as TandemApplication
        val recorder = application.activityRecorder
        val toggles = application.featureToggles
        val filesFeature = filesFeature(context, clock, recorder)
        purgeRegistry.register(filesFeature.purger)
        purgeRegistry.register(application.activityStore)
        val smsFeatures =
            SmsFeatures(
                source = ContentResolverSmsSource(context),
                sender = SmsManagerSender(context),
                sendPermission = ContextSendSmsPermission(context),
                subscriptions = SubscriptionManagerSource(context),
                elapsedRealtimeSource = SystemElapsedRealtimeSource,
                ioDispatcher = AppDispatchers.io,
            )
        val iconSettings =
            SettingsStore(
                createSettingsDataStore(File(context.filesDir, ICON_SENT_STORE_FILE_NAME), AppDispatchers.default),
            )
        return listOf(
            NotificationsFeature(SystemElapsedRealtimeSource, clock, AppDispatchers.default)
                .gatedBy(toggles, SyncFeature.Notifications),
            ClipboardFeature(
                ClipboardWriter(
                    context.getSystemService(ClipboardManager::class.java),
                    LiveClipboardSession.loopGuard,
                ) {
                    recorder.record(ActivityEventType.ClipboardFromMac)
                    showReceivedToast(context)
                },
            ).gatedBy(toggles, SyncFeature.Clipboard),
            filesFeature,
            ContactsFeature(ContentResolverContactsSource(context), AppDispatchers.io, clock),
            StatusFeature(statusAggregator(context), clock, AppDispatchers.default),
            RingFeature(
                alarmPlayer = { SystemAlarmPlayer(context) },
                policyAccess = { SystemNotificationPolicyAccess(context) },
                elapsedRealtimeSource = SystemElapsedRealtimeSource,
                onRing = { recorder.record(ActivityEventType.FindPhone) },
            ),
            callsFeature(context, clock, recorder),
            FocusFeature { SystemInterruptionFilterGateway(context) },
            NotificationInteractionsFeature(context, iconSettings, AppDispatchers.default)
                .gatedBy(toggles, SyncFeature.Notifications),
            mirrorFeature(context, clock, trustStore, keyManager, recorder)
                .gatedBy(toggles, SyncFeature.Mirroring),
            RotationFeature(
                pins = trustStore,
                clock = clock,
                random = SecureRandom(),
                eventLog = RotationEventLog { Log.w(TAG, "rotation_rejected reason=${it.name}") },
            ),
            rotation.sessionFeature(),
        ) + smsFeatures.all().map { it.gatedBy(toggles, SyncFeature.Messages) }
    }

    private fun SessionFeature.gatedBy(
        toggles: FeatureToggles,
        feature: SyncFeature,
    ): SessionFeature = GatedSessionFeature(this, toggles.enabled(feature))

    private fun callsFeature(
        context: Context,
        clock: Clock,
        recorder: ActivityRecorder,
    ): CallsFeature {
        val normalizer = PhoneNormalizer(TelephonyRegionSource(context.getSystemService(TelephonyManager::class.java)))
        return CallsFeature(
            gateway = TelecomCallGateway(context),
            permissions = ContextCallPermissions(context),
            subscriptions = SubscriptionManagerCallSubscriptions(context),
            notifier = NotificationTapToCallNotifier(context),
            emergencyNumbers = TelephonyEmergencyNumbers(context.getSystemService(TelephonyManager::class.java)),
            normalize = { normalizer.normalize(it).normalizedE164 },
            clock = clock,
            elapsedRealtimeSource = SystemElapsedRealtimeSource,
            ioDispatcher = AppDispatchers.io,
            onCallEnded = { seconds -> recorder.record(ActivityEventType.PhoneCall, durationSeconds = seconds) },
        )
    }

    private fun statusAggregator(context: Context) =
        StatusAggregator(
            BatteryReceiverStatusSource(context),
            ConnectivityManagerNetworkTypeSource(context.getSystemService(ConnectivityManager::class.java)),
            TelephonyNetworkSignalStrengthSource(context, context.getSystemService(TelephonyManager::class.java)),
        )

    private fun showReceivedToast(context: Context) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, R.string.clipboard_received, Toast.LENGTH_SHORT).show()
        }
    }

    private fun mirrorFeature(
        context: Context,
        clock: Clock,
        trustStore: TrustStore,
        keyManager: X509KeyManager,
        recorder: ActivityRecorder,
    ): MirrorFeature {
        val application = context as TandemApplication
        return MirrorFeature(
            platform = AndroidMirrorPlatform(context),
            presenter = NotificationMirrorPromptPresenter(context, MirrorConsentActivity::class.java),
            peerName = { peer ->
                trustStore.list().firstOrNull { it.spkiSha256Base64Url == peer.base64Url }?.displayName
                    ?: context.getString(R.string.mirror_peer_fallback_name)
            },
            controlAddress = { session ->
                application.sessionRegistry.current.value
                    ?.takeIf { it.session === session }
                    ?.address
            },
            mediaStreams = PinnedTlsMediaStreamFactory(keyManager),
            elapsedRealtime = SystemElapsedRealtimeSource,
            inputTarget = { LiveRemoteInput.current },
            dropLog = LogInputDropLog(),
            clock = clock,
            ioDispatcher = AppDispatchers.io,
            random = SecureRandom(),
            onMirrorEnded = { seconds -> recorder.record(ActivityEventType.Mirroring, durationSeconds = seconds) },
        )
    }

    private fun filesFeature(
        context: Context,
        clock: Clock,
        recorder: ActivityRecorder,
    ): FilesFeature {
        val mediaPermissionChecker = MediaPermissionChecker(context)
        return FilesFeature(
            store = FileTransferStore(File(context.filesDir, INCOMING_TRANSFERS_DIRECTORY), clock),
            publisher = MediaStoreDownloadsPublisher(context.contentResolver),
            notifier = recordingNotifier(NotificationReceivedFileNotifier(context), recorder),
            prompter = NotificationTransferPrompter(context),
            freeSpace = StatFsFreeSpaceProvider(context.filesDir),
            reader = ContentResolverSourceFileReader(context.contentResolver),
            mediaSource = ContentResolverMediaStoreSource(context.contentResolver),
            thumbnailLoader = ContentResolverThumbnailLoader(context.contentResolver, mediaPermissionChecker::access),
            permissionChecker = mediaPermissionChecker,
            acceptSettings = { AcceptSettings() },
            clock = clock,
            ioDispatcher = AppDispatchers.io,
            serialDispatcher = AppDispatchers::serial,
        )
    }

    private fun recordingNotifier(
        delegate: ReceivedFileNotifier,
        recorder: ActivityRecorder,
    ) = ReceivedFileNotifier { name, mime, contentUri ->
        recorder.record(ActivityEventType.FileReceived)
        delegate.notifyReceived(name, mime, contentUri)
    }

    private const val TAG = "SessionFeatureFactory"
    private const val INCOMING_TRANSFERS_DIRECTORY = "incoming-transfers"
    private const val ICON_SENT_STORE_FILE_NAME = "icon-sent.preferences_pb"
}
