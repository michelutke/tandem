package dev.tandem.app.di

import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.telephony.TelephonyManager
import android.util.Log
import dev.tandem.app.TandemApplication
import dev.tandem.app.clipboard.ClipboardWriter
import dev.tandem.app.connection.SessionFeature
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
import dev.tandem.app.ring.SystemAlarmPlayer
import dev.tandem.app.ring.SystemNotificationPolicyAccess
import dev.tandem.core.pairing.PeerDataPurgeRegistry
import dev.tandem.core.storage.rotation.RotationEventLog
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.core.storage.settings.createSettingsDataStore
import dev.tandem.core.storage.trust.TrustStore
import dev.tandem.core.transport.time.SystemElapsedRealtimeSource
import dev.tandem.feature.clipboard.LiveClipboardSession
import dev.tandem.feature.contacts.ContentResolverContactsSource
import dev.tandem.feature.files.AcceptSettings
import dev.tandem.feature.files.ContentResolverMediaStoreSource
import dev.tandem.feature.files.ContentResolverSourceFileReader
import dev.tandem.feature.files.ContentResolverThumbnailLoader
import dev.tandem.feature.files.FileTransferStore
import dev.tandem.feature.files.MediaPermissionChecker
import dev.tandem.feature.files.MediaStoreDownloadsPublisher
import dev.tandem.feature.files.NotificationReceivedFileNotifier
import dev.tandem.feature.files.NotificationTransferPrompter
import dev.tandem.feature.files.StatFsFreeSpaceProvider
import dev.tandem.feature.messaging.ContentResolverSmsSource
import dev.tandem.feature.messaging.ContextSendSmsPermission
import dev.tandem.feature.messaging.SmsManagerSender
import dev.tandem.feature.messaging.SubscriptionManagerSource
import dev.tandem.feature.notifications.SystemInterruptionFilterGateway
import dev.tandem.feature.status.BatteryReceiverStatusSource
import dev.tandem.feature.status.ConnectivityManagerNetworkTypeSource
import dev.tandem.feature.status.StatusAggregator
import dev.tandem.feature.status.TelephonyNetworkSignalStrengthSource
import java.io.File
import java.security.SecureRandom
import java.time.Clock

/**
 * The per-session consumers the connection orchestrator attaches to every Ready session (E20-23,
 * E20-24). Each reads its channel through `session.receive` (the per-session dispatcher), so there is
 * one subscriber per consumer and none competes for frames.
 */
object SessionFeatureFactory {
    fun create(
        context: Context,
        clock: Clock,
        trustStore: TrustStore,
        purgeRegistry: PeerDataPurgeRegistry,
    ): List<SessionFeature> {
        val filesFeature = filesFeature(context, clock)
        purgeRegistry.register(filesFeature.purger)
        purgeRegistry.register((context as TandemApplication).activityStore)
        val smsFeatures =
            SmsFeatures(
                source = ContentResolverSmsSource(context),
                sender = SmsManagerSender(context),
                sendPermission = ContextSendSmsPermission(context),
                subscriptions = SubscriptionManagerSource(context),
                elapsedRealtimeSource = SystemElapsedRealtimeSource,
                ioDispatcher = AppDispatchers.io,
            )
        val statusAggregator =
            StatusAggregator(
                BatteryReceiverStatusSource(context),
                ConnectivityManagerNetworkTypeSource(context.getSystemService(ConnectivityManager::class.java)),
                TelephonyNetworkSignalStrengthSource(context, context.getSystemService(TelephonyManager::class.java)),
            )
        val iconSettings =
            SettingsStore(
                createSettingsDataStore(File(context.filesDir, ICON_SENT_STORE_FILE_NAME), AppDispatchers.default),
            )
        return listOf(
            NotificationsFeature(SystemElapsedRealtimeSource, clock, AppDispatchers.default),
            ClipboardFeature(
                ClipboardWriter(context.getSystemService(ClipboardManager::class.java), LiveClipboardSession.loopGuard),
            ),
            filesFeature,
            ContactsFeature(ContentResolverContactsSource(context), AppDispatchers.io, clock),
            StatusFeature(statusAggregator, clock, AppDispatchers.default),
            RingFeature(
                alarmPlayer = { SystemAlarmPlayer(context) },
                policyAccess = { SystemNotificationPolicyAccess(context) },
                elapsedRealtimeSource = SystemElapsedRealtimeSource,
            ),
            FocusFeature { SystemInterruptionFilterGateway(context) },
            NotificationInteractionsFeature(context, iconSettings, AppDispatchers.default),
            RotationFeature(
                pins = trustStore,
                clock = clock,
                random = SecureRandom(),
                eventLog = RotationEventLog { Log.w(TAG, "rotation_rejected reason=${it.name}") },
            ),
        ) + smsFeatures.all()
    }

    private fun filesFeature(
        context: Context,
        clock: Clock,
    ): FilesFeature =
        FilesFeature(
            store = FileTransferStore(File(context.filesDir, INCOMING_TRANSFERS_DIRECTORY), clock),
            publisher = MediaStoreDownloadsPublisher(context.contentResolver),
            notifier = NotificationReceivedFileNotifier(context),
            prompter = NotificationTransferPrompter(context),
            freeSpace = StatFsFreeSpaceProvider(context.filesDir),
            reader = ContentResolverSourceFileReader(context.contentResolver),
            mediaSource = ContentResolverMediaStoreSource(context.contentResolver),
            thumbnailLoader = ContentResolverThumbnailLoader(context.contentResolver),
            permissionChecker = MediaPermissionChecker(context),
            acceptSettings = { AcceptSettings() },
            clock = clock,
            ioDispatcher = AppDispatchers.io,
            serialDispatcher = AppDispatchers::serial,
        )

    private const val TAG = "SessionFeatureFactory"
    private const val INCOMING_TRANSFERS_DIRECTORY = "incoming-transfers"
    private const val ICON_SENT_STORE_FILE_NAME = "icon-sent.preferences_pb"
}
