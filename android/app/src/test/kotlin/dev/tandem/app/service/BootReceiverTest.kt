package dev.tandem.app.service

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

// E20-08 tdd:
//   unit: bootReceiver_bootCompletedWithPairedMac_startsForegroundService
//   unit: bootReceiver_bootCompletedNoPairedMac_startsNothing
//   unit: bootReceiver_explicitIntentOtherAction_startsNothing
//   unit: bootReceiver_myPackageReplacedWithPairedMac_startsForegroundService
//
// Runs on Robolectric (E00-20): onReceive takes a Context/Intent, Android framework types.
// serviceStarterFactory/dispatcher are set before onReceive() runs (same seam as
// TandemService's pairedPeerRepositoryFactory/dispatcher), so the fake repository's
// MutableStateFlow -- already primed with a value -- resolves observeHasPairedPeer().first()
// synchronously under UnconfinedTestDispatcher instead of needing an event-loop pump.
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class BootReceiverTest {
    // The system delivers BOOT_COMPLETED/MY_PACKAGE_REPLACED as a genuinely external implicit
    // broadcast (detekt's ImplicitInternalIntent rule doc: suppress rather than add a meaningless
    // .setPackage(...) to an intent that must stay implicit to match what the platform sends).
    @Suppress("ImplicitInternalIntent")
    @Test
    fun bootReceiver_bootCompletedWithPairedMac_startsForegroundService() {
        var startCount = 0
        val receiver = buildReceiver(hasPairedPeer = true, onStart = { startCount++ })

        receiver.onReceive(RuntimeEnvironment.getApplication(), Intent(Intent.ACTION_BOOT_COMPLETED))

        assertEquals(1, startCount)
    }

    @Suppress("ImplicitInternalIntent")
    @Test
    fun bootReceiver_bootCompletedNoPairedMac_startsNothing() {
        var startCount = 0
        val receiver = buildReceiver(hasPairedPeer = false, onStart = { startCount++ })

        receiver.onReceive(RuntimeEnvironment.getApplication(), Intent(Intent.ACTION_BOOT_COMPLETED))

        assertEquals(0, startCount)
    }

    @Test
    fun bootReceiver_explicitIntentOtherAction_startsNothing() {
        var startCount = 0
        val receiver = buildReceiver(hasPairedPeer = true, onStart = { startCount++ })
        val context = RuntimeEnvironment.getApplication()
        val explicitOtherActionIntent =
            Intent("com.other.app.SOME_ACTION").setClass(context, BootReceiver::class.java)

        receiver.onReceive(context, explicitOtherActionIntent)

        assertEquals(0, startCount)
    }

    @Suppress("ImplicitInternalIntent")
    @Test
    fun bootReceiver_myPackageReplacedWithPairedMac_startsForegroundService() {
        var startCount = 0
        val receiver = buildReceiver(hasPairedPeer = true, onStart = { startCount++ })

        receiver.onReceive(RuntimeEnvironment.getApplication(), Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        assertEquals(1, startCount)
    }

    private fun buildReceiver(
        hasPairedPeer: Boolean,
        onStart: () -> Unit,
    ): BootReceiver {
        val receiver = BootReceiver()
        receiver.serviceStarterFactory = {
            ServiceStarter(
                pairedPeerRepository = FakePairedPeerRepository(hasPairedPeer),
                startForegroundService = onStart,
            )
        }
        receiver.dispatcher = UnconfinedTestDispatcher()
        return receiver
    }
}
