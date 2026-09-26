package dev.tandem.app

import android.app.Application
import android.content.Intent
import dagger.hilt.android.HiltAndroidApp
import dev.tandem.app.di.AppDispatchers
import dev.tandem.app.service.ServiceStarter
import dev.tandem.app.service.TandemService
import dev.tandem.app.service.TrustStorePairedPeerRepository
import dev.tandem.core.storage.trust.TrustStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File

/**
 * Root Hilt application (E00-03). The generated `Hilt_TandemApplication` superclass builds the
 * real `SingletonComponent` from every `@Module @InstallIn` shell on the app's classpath; no
 * production Hilt bindings live here yet.
 *
 * [onCreate] composes [ServiceStarter] with the real trust store (E13-02, F-4.1/E20-02) and
 * starts [TandemService] on app launch only when a paired Mac already exists.
 */
@HiltAndroidApp
class TandemApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        val trustStore = TrustStore.open(this, File(filesDir, TandemService.TRUST_STORE_FILE_NAME))
        val serviceStarter =
            ServiceStarter(
                pairedPeerRepository = TrustStorePairedPeerRepository(trustStore),
                startForegroundService = { startForegroundService(Intent(this, TandemService::class.java)) },
            )
        CoroutineScope(SupervisorJob() + AppDispatchers.default).launch { serviceStarter.start() }
    }
}
