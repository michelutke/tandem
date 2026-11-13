package dev.tandem.core.pairing

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.revoke.TrustRemover
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Clock
import kotlin.time.Duration.Companion.seconds

/**
 * [UnpairAction] over two real [ByteStreamSession]s on `InMemoryDuplexPipe` (E00-19): the peer must
 * see `Revoke` even though the unpairing side closes its connection right after sending.
 */
class UnpairActionRealSessionTest {
    @Test
    fun unpairAction_realSessionOverPipe_peerReceivesRevokeBeforeClose() =
        runBlocking(Dispatchers.IO) {
            repeat(REPEATS) {
                val pipe = InMemoryDuplexPipe()
                val phone = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO)
                val mac = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)
                phone.state.first { it is ConnectionState.Ready }
                mac.state.first { it is ConnectionState.Ready }
                val revoke =
                    async(start = CoroutineStart.UNDISPATCHED) {
                        mac.receive(Channel.CHANNEL_CONTROL).first { it.payloadCase == Envelope.PayloadCase.REVOKE }
                    }

                UnpairAction(TrustRemover {}, PeerDataPurgeRegistry()).unpair(SpkiFingerprint(ByteArray(32)), phone)

                assertEquals(Envelope.PayloadCase.REVOKE, withTimeout(5.seconds) { revoke.await() }.payloadCase)
                mac.close()
            }
        }

    private companion object {
        const val REPEATS = 20
    }
}
