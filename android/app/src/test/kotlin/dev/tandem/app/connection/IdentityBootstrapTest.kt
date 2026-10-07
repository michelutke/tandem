package dev.tandem.app.connection

import dev.tandem.core.pairing.IdentityUnavailableException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class IdentityBootstrapTest {
    @Test
    fun ensure_calledRepeatedlyAndConcurrently_bootstrapsOnce() =
        runTest {
            var calls = 0
            val identity = IdentityBootstrap({ calls++ }, StandardTestDispatcher(testScheduler))

            val all = List(3) { async { identity.ensure() } }
            all.forEach { it.await() }
            identity.ensure()

            assertEquals(1, calls)
        }

    @Test
    fun ensure_bootstrapFails_throwsIdentityUnavailableAndRetriesNextCall() =
        runTest {
            var calls = 0
            val identity =
                IdentityBootstrap(
                    { if (calls++ == 0) error("keystore") },
                    StandardTestDispatcher(testScheduler),
                )

            val first = async { runCatching { identity.ensure() }.exceptionOrNull() }

            assertEquals(IdentityUnavailableException::class, first.await()!!::class)
            identity.ensure()
            assertEquals(2, calls)
        }
}
