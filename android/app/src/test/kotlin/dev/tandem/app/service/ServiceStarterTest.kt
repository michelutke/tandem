package dev.tandem.app.service

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
}
