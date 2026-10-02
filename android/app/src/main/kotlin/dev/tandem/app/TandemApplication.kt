package dev.tandem.app

import android.app.Application
import android.content.Intent
import dagger.hilt.android.HiltAndroidApp
import dev.tandem.app.activity.ActivityStore
import dev.tandem.app.connection.KnownPeerStore
import dev.tandem.app.di.AppClock
import dev.tandem.app.di.AppDispatchers
import dev.tandem.app.service.ServiceStarter
import dev.tandem.app.service.SessionRegistry
import dev.tandem.app.service.TandemService
import dev.tandem.app.service.TrustStorePairedPeerRepository
import dev.tandem.core.storage.settings.createSettingsDataStore
import dev.tandem.core.storage.trust.TrustStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import kotlin.time.Duration.Companion.days

/**
 * Root Hilt application (E00-03). The generated `Hilt_TandemApplication` superclass builds the
 * real `SingletonComponent` from every `@Module @InstallIn` shell on the app's classpath; no
 * production Hilt bindings live here yet.
 *
 * [trustStore] is the one process-wide `TrustStore` instance (E13-02). Room's
 * `InvalidationTracker` -- what [TrustStore.observeList] relies on to notice writes -- is scoped
 * per `RoomDatabase` instance, so every `:app` consumer (this class's own [ServiceStarter] check,
 * [TandemService], and any future consumer such as an unpair action) reads and writes through
 * this single instance rather than each opening its own connection to the same file: two
 * independent connections would each have their own tracker and never see the other's writes,
 * so [TandemService] would never notice a write made through a different connection.
 *
 * [onCreate] composes [ServiceStarter] with [trustStore] (F-4.1/E20-02) and starts
 * [TandemService] on app launch only when a paired Mac already exists.
 */
@HiltAndroidApp
class TandemApplication : Application() {
    val trustStore: TrustStore by lazy { TrustStore.open(this, File(filesDir, TRUST_STORE_FILE_NAME)) }
    val sessionRegistry = SessionRegistry()
    val knownPeerStore: KnownPeerStore by lazy { KnownPeerStore(File(filesDir, KNOWN_PEERS_FILE_NAME)) }

    val activityStore: ActivityStore by lazy {
        ActivityStore(
            createSettingsDataStore(File(filesDir, ACTIVITY_STORE_FILE_NAME), AppDispatchers.default),
            AppClock.system,
        )
    }

    override fun onCreate() {
        super.onCreate()

        val serviceStarter =
            ServiceStarter(
                pairedPeerRepository = TrustStorePairedPeerRepository(trustStore),
                startForegroundService = { startForegroundService(Intent(this, TandemService::class.java)) },
            )
        val appScope = CoroutineScope(SupervisorJob() + AppDispatchers.default)
        appScope.launch { serviceStarter.start() }
        appScope.launch {
            while (true) {
                activityStore.purgeExpired()
                delay(1.days)
            }
        }
    }

    companion object {
        const val TRUST_STORE_FILE_NAME = "trust.db"
        const val KNOWN_PEERS_FILE_NAME = "known-peers"
        const val ACTIVITY_STORE_FILE_NAME = "activity.preferences_pb"
    }
}
