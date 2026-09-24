package dev.tandem.core.testing

import app.cash.turbine.test
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

// E00-04: proves JUnit5 + Turbine run under `./gradlew test` in a real module.
class SampleFlowTest {
    @Test
    fun sampleFlowEmitter_collectedWithTurbine_emitsOneTwoThreeThenCompletes() = runTest {
        flowOf(1, 2, 3).test {
            assertEquals(1, awaitItem())
            assertEquals(2, awaitItem())
            assertEquals(3, awaitItem())
            awaitComplete()
        }
    }
}
