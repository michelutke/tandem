package dev.tandem.core.discovery

import app.cash.turbine.test
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class PermissionGatedServiceDiscoveryTest {
    private class CountingDiscovery : ServiceDiscovery {
        var browseCalls = 0

        override fun browse(): Flow<DiscoveryEvent> {
            browseCalls++
            return emptyFlow()
        }
    }

    @Test
    fun browse_permissionMissing_neverStartsDelegateAndEmitsNothing() =
        runTest {
            val delegate = CountingDiscovery()
            val discovery = PermissionGatedServiceDiscovery(delegate) { false }

            discovery.browse().test { awaitComplete() }

            assertEquals(0, delegate.browseCalls)
        }

    @Test
    fun browse_permissionGranted_forwardsDelegateEvents() =
        runTest {
            val delegate = FakeServiceDiscovery()
            val discovery = PermissionGatedServiceDiscovery(delegate) { true }

            discovery.browse().test {
                delegate.emit(DiscoveryEvent.Found("mac-1"))
                assertEquals(DiscoveryEvent.Found("mac-1"), awaitItem())
                cancelAndIgnoreRemainingEvents()
            }
        }
}
