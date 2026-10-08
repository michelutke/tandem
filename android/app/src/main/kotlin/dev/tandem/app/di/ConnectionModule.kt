package dev.tandem.app.di

import android.app.Application
import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.nsd.NsdManager
import android.os.PowerManager
import android.telephony.TelephonyManager
import android.util.Log
import dagger.Module
import dagger.Provides
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.tandem.app.TandemApplication
import dev.tandem.app.clipboard.ClipboardWriter
import dev.tandem.app.connection.ActivityForegroundSource
import dev.tandem.app.connection.ConnectionOrchestrator
import dev.tandem.app.connection.ConnectionStatusViewModel
import dev.tandem.app.connection.FeatureAttacher
import dev.tandem.app.connection.IdentityBootstrap
import dev.tandem.app.connection.KnownPeerStore
import dev.tandem.app.connection.PairedFingerprints
import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.app.connection.PendingRotationSessionDialer
import dev.tandem.app.connection.SessionFeature
import dev.tandem.app.connection.TlsManualPairingConnector
import dev.tandem.app.connection.TlsPairingConnector
import dev.tandem.app.connection.TlsSessionDialer
import dev.tandem.app.connection.TrustStoreCommitter
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
import dev.tandem.app.connection.orchestratorConnectionState
import dev.tandem.app.onboarding.hasLocalNetworkAccess
import dev.tandem.app.ring.SystemAlarmPlayer
import dev.tandem.app.ring.SystemNotificationPolicyAccess
import dev.tandem.app.service.SessionRegistry
import dev.tandem.app.settings.ROTATION_INTERVAL_DAYS_KEY
import dev.tandem.app.settings.rotationInterval
import dev.tandem.app.shell.PairingFlow
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.AndroidKeyStoreIdentityKeyStore
import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.IdentityKeyProvider
import dev.tandem.core.discovery.NsdManagerSource
import dev.tandem.core.discovery.NsdServiceDiscovery
import dev.tandem.core.discovery.PairedMacMatcher
import dev.tandem.core.discovery.PermissionGatedServiceDiscovery
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.pairing.PeerDataPurgeRegistry
import dev.tandem.core.pairing.PeerDataPurging
import dev.tandem.core.pairing.SystemDeviceInfoProvider
import dev.tandem.core.pairing.UnpairAction
import dev.tandem.core.pairing.revoke.TrustRemover
import dev.tandem.core.pairing.rotation.FileNextRotationDueStore
import dev.tandem.core.pairing.rotation.RotationKeys
import dev.tandem.core.storage.rotation.RotationEventLog
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.core.storage.settings.createSettingsDataStore
import dev.tandem.core.storage.trust.TrustStore
import dev.tandem.core.transport.HeartbeatDependencies
import dev.tandem.core.transport.heartbeat.PowerManagerDeviceIdleSource
import dev.tandem.core.transport.reconnect.ConnectivityManagerNetworkMonitor
import dev.tandem.core.transport.reconnect.PairedMacBonjourSource
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import java.io.File
import java.security.SecureRandom
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
 * Candidates come from Bonjour plus the addresses stored at pairing ([PairingAddressStore]); the
 * pinned handshake alone decides trust.
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
    fun pairingFlow(
        trustStore: TrustStore,
        activeIdentityAlias: ActiveIdentityAlias,
        identityBootstrap: IdentityBootstrap,
    ): PairingFlow {
        val clock = AppClock.system
        return PairingFlow(
            clock = clock,
            dispatcher = AppDispatchers.default,
            connector =
                TlsPairingConnector(
                    keyManager = IdentityKeyManager(AndroidKeyStoreIdentityKeyStore(clock), activeIdentityAlias),
                    clock = clock,
                    ioDispatcher = AppDispatchers.io,
                    sessionDispatcher = AppDispatchers.io,
                    identity = identityBootstrap,
                ),
            trustCommitter = TrustStoreCommitter(trustStore::put),
            deviceInfoProvider = SystemDeviceInfoProvider,
            manualConnector =
                TlsManualPairingConnector(
                    keyManager = IdentityKeyManager(AndroidKeyStoreIdentityKeyStore(clock), activeIdentityAlias),
                    clock = clock,
                    ioDispatcher = AppDispatchers.io,
                    sessionDispatcher = AppDispatchers.io,
                    identity = identityBootstrap,
                ),
        )
    }

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
    fun pairingAddressStore(
        @ApplicationContext context: Context,
        purgeRegistry: PeerDataPurgeRegistry,
    ): PairingAddressStore =
        PairingAddressStore(File(context.filesDir, PAIRING_ADDRESSES_FILE_NAME)).also { store ->
            purgeRegistry.register(PeerDataPurging { store.clear() })
        }

    @Provides
    @Singleton
    fun pairedFingerprints(trustStore: TrustStore): PairedFingerprints =
        PairedFingerprints(trustStore, AppClock.system, AppDispatchers.default)

    @Provides
    @Singleton
    fun unpairAction(
        trustStore: TrustStore,
        purgeRegistry: PeerDataPurgeRegistry,
    ): UnpairAction = UnpairAction(TrustRemover { trustStore.unpair(it) }, purgeRegistry)

    @Provides
    @Singleton
    fun connectionStatusViewModel(
        orchestrator: ConnectionOrchestrator,
        sessionRegistry: SessionRegistry,
        trustStore: TrustStore,
    ): ConnectionStatusViewModel {
        val scope = CoroutineScope(SupervisorJob() + AppDispatchers.default)
        return ConnectionStatusViewModel(
            connectionState = orchestratorConnectionState(sessionRegistry, orchestrator.failure, scope),
            failedCycles = orchestrator.failedCycles,
            macName =
                trustStore
                    .observeList()
                    .map { records -> records.firstOrNull()?.displayName }
                    .stateIn(scope, SharingStarted.Eagerly, null),
        )
    }

    @Suppress("LongParameterList") // Hilt-injected graph nodes the connect loop is composed from
    @Provides
    @Singleton
    fun connectionOrchestrator(
        @ApplicationContext context: Context,
        sessionRegistry: SessionRegistry,
        knownPeerStore: KnownPeerStore,
        pairedFingerprints: PairedFingerprints,
        purgeRegistry: PeerDataPurgeRegistry,
        pairingAddressStore: PairingAddressStore,
        activeIdentityAlias: ActiveIdentityAlias,
        trustStore: TrustStore,
        rotation: RotationComposition,
        identityBootstrap: IdentityBootstrap,
    ): ConnectionOrchestrator {
        val clock = AppClock.system
        val idleSource = startedIdleSource(context)
        val keyManager = IdentityKeyManager(AndroidKeyStoreIdentityKeyStore(clock), activeIdentityAlias)
        val keyStore = AndroidKeyStoreIdentityKeyStore(clock)
        val heartbeatDependencies = HeartbeatDependencies(SystemElapsedRealtimeSource, idleSource)
        val dialer =
            PendingRotationSessionDialer(
                handshake = rotation.pendingHandshake,
                dialerFor = { alias ->
                    TlsSessionDialer(
                        keyManager = IdentityKeyManager(keyStore, alias),
                        identity = identityBootstrap,
                        pinnedFingerprints = pairedFingerprints::load,
                        wasPreviouslyPinned = knownPeerStore::hasEverPinned,
                        clock = clock,
                        ioDispatcher = AppDispatchers.io,
                        sessionDispatcher = AppDispatchers.io,
                        heartbeatDependencies = heartbeatDependencies,
                    )
                },
                onAuthenticated = { rotation.refreshFingerprint() },
            )
        startRotationScheduler(context, clock, rotation)
        val bonjourSource =
            PairedMacBonjourSource(
                discovery =
                    PermissionGatedServiceDiscovery(
                        delegate =
                            NsdServiceDiscovery(
                                NsdManagerSource(context.getSystemService(NsdManager::class.java)),
                                AppDispatchers.default,
                            ),
                        hasLocalNetworkAccess = { hasLocalNetworkAccess(context) },
                    ),
                matcher = PairedMacMatcher(clock),
                pairedFingerprints = pairedFingerprints::snapshot,
                dispatcher = AppDispatchers.default,
            )
        val features = SessionFeatureFactory.create(context, clock, trustStore, purgeRegistry, keyManager, rotation)
        return ConnectionOrchestrator(
            dialer = dialer,
            registry = sessionRegistry,
            featureAttacher = FeatureAttacher(features) { Log.e(TAG, "Session feature failed: ${it.javaClass.name}") },
            knownPeerStore = knownPeerStore,
            bonjourSource = bonjourSource,
            pairingAddressSource = pairingAddressStore,
            networkMonitor =
                ConnectivityManagerNetworkMonitor(context.getSystemService(ConnectivityManager::class.java)),
            deviceIdleSource = idleSource,
            foreground = ActivityForegroundSource(context.applicationContext as Application).foregrounded,
            clock = clock,
            dispatcher = AppDispatchers.default,
            warn = { Log.w(TAG, it) },
        )
    }

    private const val TAG = "ConnectionModule"
    private const val PAIRING_ADDRESSES_FILE_NAME = "pairing-addresses"
}

private fun startedIdleSource(context: Context) =
    PowerManagerDeviceIdleSource(context, context.getSystemService(PowerManager::class.java)).also { it.start() }

private fun startRotationScheduler(
    context: Context,
    clock: Clock,
    rotation: RotationComposition,
) {
    val settings =
        SettingsStore(
            createSettingsDataStore(File(context.filesDir, "rotation-settings.preferences_pb"), AppDispatchers.default),
        )
    val dueStore = FileNextRotationDueStore(File(context.filesDir, "next-rotation-due"))
    CoroutineScope(SupervisorJob() + AppDispatchers.default).launch {
        rotation.runScheduler(clock, dueStore, settings.get(ROTATION_INTERVAL_DAYS_KEY).map(::rotationInterval))
    }
}
