package dev.tandem.app.di

import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.nsd.NsdManager
import android.os.PowerManager
import android.util.Log
import dagger.Module
import dagger.Provides
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.tandem.app.TandemApplication
import dev.tandem.app.clipboard.ClipboardWriter
import dev.tandem.app.connection.ConnectionOrchestrator
import dev.tandem.app.connection.FeatureAttacher
import dev.tandem.app.connection.KnownPeerStore
import dev.tandem.app.connection.PairedFingerprints
import dev.tandem.app.connection.TlsSessionDialer
import dev.tandem.app.connection.feature.ClipboardFeature
import dev.tandem.app.connection.feature.FilesFeature
import dev.tandem.app.connection.feature.NotificationsFeature
import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.crypto.AndroidKeyStoreIdentityKeyStore
import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.discovery.NsdManagerSource
import dev.tandem.core.discovery.NsdServiceDiscovery
import dev.tandem.core.discovery.PairedMacMatcher
import dev.tandem.core.pairing.PeerDataPurgeRegistry
import dev.tandem.core.storage.trust.TrustStore
import dev.tandem.core.transport.HeartbeatDependencies
import dev.tandem.core.transport.heartbeat.PowerManagerDeviceIdleSource
import dev.tandem.core.transport.reconnect.ConnectivityManagerNetworkMonitor
import dev.tandem.core.transport.reconnect.PairedMacBonjourSource
import dev.tandem.core.transport.reconnect.PairingAddressSource
import dev.tandem.core.transport.time.SystemElapsedRealtimeSource
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
import java.io.File
import java.time.Clock
import javax.inject.Singleton

/** Entry point [dev.tandem.app.service.TandemService] (framework-constructed) resolves its loop through. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface ConnectionEntryPoint {
    fun connectionOrchestrator(): ConnectionOrchestrator
}

/**
 * Process singletons for the production connection (E20-23). The stores stay owned by
 * [TandemApplication] (one Room/file connection each); this module only exposes them to the graph.
 * Paired Macs are found by Bonjour only: there is no stored pairing-address source yet, so that
 * candidate source is empty.
 */
@Module
@InstallIn(SingletonComponent::class)
object ConnectionModule {
    @Provides
    @Singleton
    fun trustStore(
        @ApplicationContext context: Context,
    ): TrustStore = (context as TandemApplication).trustStore

    @Provides
    @Singleton
    fun sessionRegistry(
        @ApplicationContext context: Context,
    ): SessionRegistry = (context as TandemApplication).sessionRegistry

    @Provides
    @Singleton
    fun knownPeerStore(
        @ApplicationContext context: Context,
    ): KnownPeerStore = (context as TandemApplication).knownPeerStore

    @Provides
    @Singleton
    fun peerDataPurgeRegistry(): PeerDataPurgeRegistry = PeerDataPurgeRegistry()

    @Provides
    @Singleton
    fun pairedFingerprints(trustStore: TrustStore): PairedFingerprints =
        PairedFingerprints(trustStore, AppDispatchers.default)

    @Provides
    @Singleton
    fun connectionOrchestrator(
        @ApplicationContext context: Context,
        sessionRegistry: SessionRegistry,
        knownPeerStore: KnownPeerStore,
        pairedFingerprints: PairedFingerprints,
        purgeRegistry: PeerDataPurgeRegistry,
    ): ConnectionOrchestrator {
        val clock = AppClock.system
        val idleSource =
            PowerManagerDeviceIdleSource(
                context,
                context.getSystemService(PowerManager::class.java),
            ).also { it.start() }
        val dialer =
            TlsSessionDialer(
                keyManager = IdentityKeyManager(AndroidKeyStoreIdentityKeyStore(clock)),
                pinnedFingerprints = pairedFingerprints::load,
                wasPreviouslyPinned = knownPeerStore::hasEverPinned,
                clock = clock,
                ioDispatcher = AppDispatchers.io,
                sessionDispatcher = AppDispatchers.io,
                heartbeatDependencies = HeartbeatDependencies(SystemElapsedRealtimeSource, idleSource),
            )
        val bonjourSource =
            PairedMacBonjourSource(
                discovery =
                    NsdServiceDiscovery(
                        NsdManagerSource(context.getSystemService(NsdManager::class.java)),
                        AppDispatchers.default,
                    ),
                matcher = PairedMacMatcher(clock),
                pairedFingerprints = pairedFingerprints::snapshot,
                dispatcher = AppDispatchers.default,
            )
        val filesFeature = filesFeature(context, clock)
        purgeRegistry.register(filesFeature.purger)
        purgeRegistry.register((context as TandemApplication).activityStore)
        val features =
            listOf(
                NotificationsFeature(SystemElapsedRealtimeSource, clock, AppDispatchers.default),
                ClipboardFeature(ClipboardWriter(context.getSystemService(ClipboardManager::class.java))),
                filesFeature,
            )
        return ConnectionOrchestrator(
            dialer = dialer,
            registry = sessionRegistry,
            featureAttacher = FeatureAttacher(features) { Log.e(TAG, "Session feature failed: ${it.javaClass.name}") },
            knownPeerStore = knownPeerStore,
            bonjourSource = bonjourSource,
            pairingAddressSource = PairingAddressSource { emptyList() },
            networkMonitor =
                ConnectivityManagerNetworkMonitor(context.getSystemService(ConnectivityManager::class.java)),
            clock = clock,
            dispatcher = AppDispatchers.default,
            warn = { Log.w(TAG, it) },
        )
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

    private const val TAG = "ConnectionModule"
    private const val INCOMING_TRANSFERS_DIRECTORY = "incoming-transfers"
}
