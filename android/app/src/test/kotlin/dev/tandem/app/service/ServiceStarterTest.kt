package dev.tandem.app.service

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

// E20-02 tdd:
//   unit: serviceStarter_pairedMacExists_startsForegroundService
//   unit: serviceStarter_noPairedMac_doesNotStartService
class ServiceStarterTest {
    @Test
    fun serviceStarter_pairedMacExists_startsForegroundService() =
        runTest {
            var startCount = 0
            val starter =
                ServiceStarter(
                    pairedPeerRepository = FakePairedPeerRepository(hasPairedPeer = true),
                    startForegroundService = { startCount++ },
                )

            starter.start()

            assertEquals(1, startCount)
        }

    @Test
    fun serviceStarter_noPairedMac_doesNotStartService() =
        runTest {
            var startCount = 0
            val starter =
                ServiceStarter(
                    pairedPeerRepository = FakePairedPeerRepository(hasPairedPeer = false),
                    startForegroundService = { startCount++ },
                )

            starter.start()

            assertEquals(0, startCount)
        }

    @Test
    fun keepStarted_pairingCommitsAfterLaunch_startsForegroundService() =
        runTest {
            var startCount = 0
            val hasPairedPeer = MutableStateFlow(false)
            val starter = ServiceStarter(FakePairedPeerRepository(hasPairedPeer)) { startCount++ }

            val job = launch(start = CoroutineStart.UNDISPATCHED) { starter.keepStarted() }
            assertEquals(0, startCount)

            hasPairedPeer.value = true
            testScheduler.advanceUntilIdle()

            assertEquals(1, startCount)
            job.cancel()
        }

    @Test
    fun keepStarted_pairedAtLaunch_startsForegroundServiceOnce() =
        runTest {
            var startCount = 0
            val starter = ServiceStarter(FakePairedPeerRepository(hasPairedPeer = true)) { startCount++ }

            val job = launch(start = CoroutineStart.UNDISPATCHED) { starter.keepStarted() }
            testScheduler.advanceUntilIdle()

            assertEquals(1, startCount)
            job.cancel()
        }

    @Test
    fun keepStarted_noPairedMac_doesNotStartService() =
        runTest {
            var startCount = 0
            val starter = ServiceStarter(FakePairedPeerRepository(hasPairedPeer = false)) { startCount++ }

            val job = launch(start = CoroutineStart.UNDISPATCHED) { starter.keepStarted() }
            testScheduler.advanceUntilIdle()

            assertEquals(0, startCount)
            job.cancel()
        }
}
