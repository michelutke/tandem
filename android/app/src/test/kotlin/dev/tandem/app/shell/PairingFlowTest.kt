package dev.tandem.app.shell

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.DeviceInfoProvider
import dev.tandem.core.pairing.PairingConnection
import dev.tandem.core.pairing.PairingConnector
import dev.tandem.core.pairing.PairingFailure
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.pairing.TrustCommitter
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.PairRejectedReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.pairAccepted
import dev.tandem.protocol.v1.pairChallenge
import dev.tandem.protocol.v1.pairRejected
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

// E20-26 tdd:
//   unit: productionPairingStarter_confirmedMatchingCodes_commitsPinOnce
//   unit: productionPairingStarter_rejectedOrBadProof_commitsNothing
@OptIn(ExperimentalCoroutinesApi::class)
class PairingFlowTest {
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
    private val fingerprint = ByteArray(32) { it.toByte() }
    private val invite =
        PairingInvite(fingerprint, ByteArray(16) { 3 }, listOf("192.168.1.1"), 8443, "Study Mac")

    @Test
    fun productionPairingStarter_confirmedMatchingCodes_commitsPinOnce() =
        runTest {
            val rig = Rig(this)
            rig.reachAwaitingUserConfirm()

            rig.flow.confirmCodesMatch()
            rig.flow.confirmCodesMatch()
            runCurrent()

            assertEquals(PairingState.Paired, rig.flow.state.value)
            assertEquals(1, rig.commits.size)
            assertEquals(
                SpkiFingerprint(fingerprint).base64Url,
                rig.commits
                    .single()
                    .fingerprint.base64Url,
            )
            assertEquals("Study Mac", rig.commits.single().macName)
        }

    @Test
    fun productionPairingStarter_awaitingUserConfirm_commitsNothingBeforeConfirmation() =
        runTest {
            val rig = Rig(this)
            rig.reachAwaitingUserConfirm()

            assertTrue(rig.commits.isEmpty())
        }

    @Test
    fun productionPairingStarter_rejectedOrBadProof_commitsNothing() =
        runTest {
            val rig = Rig(this)
            rig.reachAwaitingAccept()

            rig.session.emitIncoming(rejectedEnvelope(PairRejectedReason.PAIR_REJECTED_REASON_PAIRING_UNAVAILABLE))
            runCurrent()

            assertEquals(
                PairingState.Rejected(PairRejectedReason.PAIR_REJECTED_REASON_PAIRING_UNAVAILABLE),
                rig.flow.state.value,
            )
            assertTrue(rig.commits.isEmpty())
        }

    @Test
    fun productionPairingStarter_rejectedByOwner_commitsNothing() =
        runTest {
            val rig = Rig(this)
            rig.reachAwaitingAccept()

            rig.session.emitIncoming(rejectedEnvelope(PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER))
            runCurrent()

            assertTrue(rig.flow.state.value is PairingState.Rejected)
            assertTrue(rig.commits.isEmpty())
        }

    @Test
    fun productionPairingStarter_expiredInvite_noAcceptNeverCommits() =
        runTest {
            val rig = Rig(this)
            rig.reachAwaitingAccept()

            advanceTimeBy(121_000)
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.Timeout), rig.flow.state.value)
            assertTrue(rig.commits.isEmpty())
        }

    @Test
    fun productionPairingStarter_userRejectsCodes_commitsNothingAndFails() =
        runTest {
            val rig = Rig(this)
            rig.reachAwaitingUserConfirm()

            rig.flow.cancel()
            runCurrent()
            rig.flow.confirmCodesMatch()
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.UserCancelled), rig.flow.state.value)
            assertTrue(rig.commits.isEmpty())
        }

    @Test
    fun productionPairingStarter_unreachableMac_failsClosedWithoutCommit() =
        runTest {
            val rig = Rig(this, connector = { _, _, _ -> error("pin mismatch") })

            rig.flow.start(invite)
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.AllAddressesUnreachable), rig.flow.state.value)
            assertTrue(rig.commits.isEmpty())
        }

    @Test
    fun productionPairingStarter_reset_returnsToIdle() =
        runTest {
            val rig = Rig(this, connector = { _, _, _ -> error("refused") })
            rig.flow.start(invite)
            runCurrent()

            rig.flow.reset()
            runCurrent()

            assertEquals(PairingState.Idle, rig.flow.state.value)
        }

    private inner class Rig(
        scope: TestScope,
        connector: PairingConnector? = null,
    ) {
        val session = FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }
        val commits = mutableListOf<Commit>()
        private val testScope = scope
        val flow =
            PairingFlow(
                clock = TestClock(scope.testScheduler),
                dispatcher = StandardTestDispatcher(scope.testScheduler),
                connector =
                    connector
                        ?: PairingConnector { _, _, _ -> PairingConnection(session, macSpkiDer, phoneSpkiDer) },
                trustCommitter = { fp, name, at -> commits += Commit(fp, name, at) },
                deviceInfoProvider =
                    object : DeviceInfoProvider {
                        override fun displayName() = "Pixel"

                        override fun model() = "Pixel 9"
                    },
            )

        fun reachAwaitingAccept() {
            flow.start(invite)
            testScope.runCurrent()
            session.emitIncoming(challengeEnvelope())
            testScope.runCurrent()
            assertTrue(flow.state.value is PairingState.AwaitingAccept)
        }

        fun reachAwaitingUserConfirm() {
            reachAwaitingAccept()
            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTROL
                    pairAccepted = pairAccepted {}
                },
            )
            testScope.runCurrent()
            assertTrue(flow.state.value is PairingState.AwaitingUserConfirm)
        }
    }

    private class Commit(
        val fingerprint: SpkiFingerprint,
        val macName: String,
        val pairedAt: Instant,
    )

    private fun challengeEnvelope(): Envelope {
        val bytes = ByteString.copyFrom(ByteArray(32) { (it * 5).toByte() })
        return envelope {
            channel = Channel.CHANNEL_CONTROL
            pairChallenge = pairChallenge { challenge = bytes }
        }
    }

    private fun rejectedEnvelope(rejectedReason: PairRejectedReason): Envelope =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            pairRejected = pairRejected { reason = rejectedReason }
        }
}

private fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) {
        hex.substring(it * 2, it * 2 + 2).toInt(16).toByte()
    }
