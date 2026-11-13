package dev.tandem.core.pairing

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.PairRejectedReason
import dev.tandem.protocol.v1.pairChallenge
import dev.tandem.protocol.v1.pairRejected
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.Instant
import kotlin.time.Duration.Companion.seconds

/**
 * [PairingStateMachine] over two real [ByteStreamSession]s wired through `InMemoryDuplexPipe`
 * (E00-19), so a peer close travels the same path a real Mac close does, with no fake driving
 * `emitState`. Real threads, like `ByteStreamSessionTest`.
 */
class PairingStateMachineRealSessionTest {
    private val macSpkiDer =
        hexToBytes(
            "3059301306072a8648ce3d020106082a8648ce3d0301070342000440" +
                "5a9ef39f6fa9344fc391b37e9af91ce7de69ebb0ca38c5d42e23d19b8233e451cd65d30c3c541" +
                "00e2427bafd64be9f9c084214bd2b66d5724d04dd18dacc79",
        )
    private val phoneSpkiDer =
        hexToBytes(
            "3059301306072a8648ce3d020106082a8648ce3d03010703420004068" +
                "0ce82b4232a0150b95909aec7fad7aac320ac498875331566dab9a5c9e79a77d45c35c83d9aec" +
                "406a2be4f340194acb3ab91dd2b31d6575e1c846e9c8e3c0",
        )
    private val invite =
        PairingInvite(
            fingerprint = ByteArray(FINGERPRINT_BYTES) { it.toByte() },
            secret = ByteArray(SECRET_BYTES) { it.toByte() },
            addresses = listOf("192.168.1.1"),
            port = 8443,
            macName = "Study Mac",
        )

    private fun awaitingAcceptThen(peerAction: suspend (ByteStreamSession) -> Unit): PairingState =
        runBlocking(Dispatchers.IO) {
            val pipe = InMemoryDuplexPipe()
            val phoneSession = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO)
            val macSession = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)
            val connector =
                PairingConnector { _: String, _: Int, _: PinSource ->
                    PairingConnection(phoneSession, macSpkiDer, phoneSpkiDer)
                }
            val sm =
                PairingStateMachine(
                    Clock.systemUTC(),
                    Dispatchers.IO,
                    connector,
                    { _: SpkiFingerprint, _: String, _: Instant -> },
                    invite,
                    object : DeviceInfoProvider {
                        override fun displayName(): String = "Test Phone"

                        override fun model(): String = "Pixel 8"
                    },
                )
            macSession.state.first { it is ConnectionState.Ready }

            sm.start()
            macSession.send(Channel.CHANNEL_CONTROL) {
                pairChallenge = pairChallenge { challenge = ByteString.copyFrom(ByteArray(CHALLENGE_BYTES)) }
            }
            withTimeout(5.seconds) { sm.state.first { it is PairingState.AwaitingAccept } }
            peerAction(macSession)

            val terminal =
                withTimeout(5.seconds) {
                    sm.state.first {
                        it is PairingState.Failed ||
                            it is PairingState.Rejected
                    }
                }
            sm.close()
            terminal
        }

    @Test
    fun pairingSm_realSessionPeerClosesWhileAwaitingAccept_emitsFailedConnectionLost() {
        val terminal = awaitingAcceptThen { it.close() }

        assertEquals(PairingState.Failed(PairingFailure.ConnectionLost), terminal)
    }

    @Test
    fun pairingSm_realSessionPeerSendsRejectedThenCloses_emitsRejectedNotConnectionLost() {
        val terminal =
            awaitingAcceptThen { mac ->
                mac.sendFinal(Channel.CHANNEL_CONTROL) {
                    pairRejected = pairRejected { reason = PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER }
                }
            }

        assertEquals(PairingState.Rejected(PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER), terminal)
    }

    private fun hexToBytes(hex: String): ByteArray =
        ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

    private companion object {
        const val FINGERPRINT_BYTES = 32
        const val SECRET_BYTES = 16
        const val CHALLENGE_BYTES = 32
    }
}
