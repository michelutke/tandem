package dev.tandem.feature.calls

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class IncomingNumberRelayTest {
    @Test
    fun incomingNumberRelay_numberPublishedBeforeAwait_returnsItImmediately() =
        runTest {
            val relay = IncomingNumberRelay()
            relay.publish("+41791234567")

            assertEquals("+41791234567", relay.await(500))
        }

    @Test
    fun incomingNumberRelay_numberPublishedWhileWaiting_returnsIt() =
        runTest {
            val relay = IncomingNumberRelay()
            val waiting = async { relay.await(500) }
            runCurrent()
            advanceTimeBy(100)
            relay.publish("+41791234567")

            assertEquals("+41791234567", waiting.await())
        }

    @Test
    fun incomingNumberRelay_nothingPublished_timesOutWithNull() =
        runTest {
            assertNull(IncomingNumberRelay().await(500))
        }

    @Test
    fun incomingNumberRelay_cleared_dropsTheNumber() =
        runTest {
            val relay = IncomingNumberRelay()
            relay.publish("+41791234567")
            relay.clear()

            assertNull(relay.peek())
            assertNull(relay.await(500))
        }
}
