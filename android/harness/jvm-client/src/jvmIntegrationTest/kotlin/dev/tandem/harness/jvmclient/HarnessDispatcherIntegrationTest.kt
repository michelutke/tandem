package dev.tandem.harness.jvmclient

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.core.transport.ByteStreamSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.time.Clock
import java.util.concurrent.Executors

/**
 * Regression test for the E12-13 dispatcher deadlock found running the harness CLI against the
 * real Mac listener: [HarnessCli]'s original `main()` drove [ByteStreamSession] with a
 * single-thread `Executors.newSingleThreadExecutor` dispatcher. [ByteStreamSession] needs that
 * dispatcher to run its `ChannelMultiplexer` read loop and its `VersionHandshake` write
 * concurrently -- both are blocking calls via `runInterruptible` (see that class's own kdoc and
 * `core/transport`'s `ByteStreamSessionTest`, which already requires `Dispatchers.IO` for the same
 * reason). A single-thread dispatcher's one thread gets permanently occupied by the read loop's
 * blocking read (there is nothing to read until the peer's hello arrives, and the peer never gets
 * one to react to because this side's own hello write never runs), so `Ready` is never reached --
 * not even after the 5 s `VersionHello` deadline, since that deadline's own timer coroutine is
 * starved of the same one thread. `main()`'s fix is to use [Dispatchers.IO] instead.
 */
class HarnessDispatcherIntegrationTest {
    @Test
    fun byteStreamSession_singleThreadDispatcher_neverReachesReady() {
        val singleThreadExecutor = Executors.newSingleThreadExecutor()
        try {
            val pipe = InMemoryDuplexPipe()
            val deadlockedClient =
                ByteStreamSession(pipe.endpointA, Clock.systemUTC(), singleThreadExecutor.asCoroutineDispatcher())
            val wellBehavedPeer = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)
            try {
                assertThrows(TimeoutCancellationException::class.java) {
                    runBlocking {
                        withTimeout(DEADLOCK_PROOF_TIMEOUT_MS) {
                            deadlockedClient.state.first { it is ConnectionState.Ready }
                        }
                    }
                }
            } finally {
                deadlockedClient.close()
                wellBehavedPeer.close()
            }
        } finally {
            singleThreadExecutor.shutdownNow()
        }
    }

    @Test
    fun byteStreamSession_ioDispatcher_reachesReady() {
        val pipe = InMemoryDuplexPipe()
        val client = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO)
        val peer = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)
        try {
            runBlocking {
                withTimeout(READY_TIMEOUT_MS) {
                    client.state.first { it is ConnectionState.Ready }
                    peer.state.first { it is ConnectionState.Ready }
                }
            }
        } finally {
            client.close()
            peer.close()
        }
    }

    private companion object {
        const val DEADLOCK_PROOF_TIMEOUT_MS = 2_000L
        const val READY_TIMEOUT_MS = 5_000L
    }
}
