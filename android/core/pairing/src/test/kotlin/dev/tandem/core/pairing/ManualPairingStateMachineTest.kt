package dev.tandem.core.pairing

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ManualPairingContext
import dev.tandem.core.crypto.ManualPairingSas
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.commitment
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.manualPairResult
import dev.tandem.protocol.v1.pairChallenge
import dev.tandem.protocol.v1.reveal
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

/**
 * Manual pairing state machine (E73-03; `docs/planning/backlog/phase-7.yaml` E73-03's `tdd:` list,
 * ADR-008). Every machine runs against a [FakeTandemSession] and virtual time; nothing opens a socket.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ManualPairingStateMachineTest {
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
    private val challenge = hexToBytes("83f7523553c91d478b4a6809c3864afc28d8b061bcaa6e5c148509b6cc2caa96")
    private val noncePhone = ByteArray(16) { 0x11 }
    private val nonceMac = ByteArray(16) { 0x22 }
    private val context = ManualPairingContext(macSpkiDer, phoneSpkiDer, challenge)
    private val address = checkNotNull(ManualPairingAddress.parse("192.168.1.10:62747"))

    @Test
    fun manualPairing_userConfirmsMatchingSas_pinsExactlyOnePeerRecord() =
        runTest {
            val rig = Rig(this)
            rig.reachSasOnScreen()
            val sas = ManualPairingSas.sas(noncePhone, nonceMac, context)
            assertEquals(PairingState.ComparingCodes(sas), rig.machine.state.value)

            rig.session.emitIncoming(manualPairResult(accepted = true))
            runCurrent()
            assertEquals(PairingState.AwaitingUserConfirm(sas, "Mac", manual = true), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())

            rig.machine.confirmCodesMatch()
            runCurrent()

            assertEquals(PairingState.Paired, rig.machine.state.value)
            assertEquals(1, rig.committer.commits.size)
            assertEquals(
                spkiFingerprint(macSpkiDer).base64Url,
                rig.committer.commits
                    .single()
                    .base64Url,
            )
        }

    @Test
    fun manualPairing_phoneRevealsOnlyAfterMacCommitment() =
        runTest {
            val rig = Rig(this)
            rig.start()
            rig.session.emitIncoming(challengeEnvelope())
            runCurrent()

            assertEquals(listOf(Envelope.PayloadCase.COMMITMENT), rig.sentCases())

            rig.session.emitIncoming(macCommitmentEnvelope())
            runCurrent()

            assertEquals(listOf(Envelope.PayloadCase.COMMITMENT, Envelope.PayloadCase.REVEAL), rig.sentCases())
        }

    @Test
    fun manualPairing_userReportsMismatchWhileComparing_abortsWithoutPinning() =
        runTest {
            val rig = Rig(this)
            rig.reachSasOnScreen()

            rig.machine.cancelConfirm()
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.UserCancelled), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())
            assertTrue(Envelope.PayloadCase.REVOKE in rig.sentCases())
        }

    @Test
    fun manualPairing_userReportsMismatchAfterMacAccepted_abortsWithoutPinning() =
        runTest {
            val rig = Rig(this)
            rig.reachSasOnScreen()
            rig.session.emitIncoming(manualPairResult(accepted = true))
            runCurrent()

            rig.machine.cancelConfirm()
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.UserCancelled), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())
        }

    @Test
    fun manualPairing_codesMatchTappedBeforeMacAccepted_pinsNothing() =
        runTest {
            val rig = Rig(this)
            rig.reachSasOnScreen()

            rig.machine.confirmCodesMatch()
            runCurrent()

            assertTrue(rig.committer.commits.isEmpty())
            assertTrue(rig.machine.state.value is PairingState.ComparingCodes)
        }

    @Test
    fun manualPairing_revealBeforePeerCommitment_abortsWithoutPinning() =
        runTest {
            val rig = Rig(this)
            rig.start()
            rig.session.emitIncoming(challengeEnvelope())
            runCurrent()

            rig.session.emitIncoming(revealEnvelope(nonceMac))
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ProtocolViolation), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())
            assertTrue(Envelope.PayloadCase.REVEAL !in rig.sentCases())
        }

    @Test
    fun manualPairing_revealMismatchesCommitment_abortsWithoutPinning() =
        runTest {
            val rig = Rig(this)
            rig.start()
            rig.session.emitIncoming(challengeEnvelope())
            runCurrent()
            rig.session.emitIncoming(macCommitmentEnvelope())
            runCurrent()

            rig.session.emitIncoming(revealEnvelope(ByteArray(16) { 0x33 }))
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ProtocolViolation), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())
        }

    @Test
    fun manualPairingVerifier_fingerprintPrefixMatchOnly_rejected() =
        runTest {
            val rig = Rig(this)
            rig.start()
            rig.session.emitIncoming(challengeEnvelope())
            runCurrent()
            rig.session.emitIncoming(macCommitmentEnvelope())
            runCurrent()
            val macFingerprint: SpkiFingerprint = spkiFingerprint(macSpkiDer)

            rig.session.emitIncoming(revealEnvelope(macFingerprint.bytes.copyOfRange(0, 16)))
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ProtocolViolation), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())
        }

    @Test
    fun manualPairing_manualPairResultNotAccepted_abortsWithoutPinning() =
        runTest {
            val rig = Rig(this)
            rig.reachSasOnScreen()

            rig.session.emitIncoming(manualPairResult(accepted = false))
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ProtocolViolation), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())
        }

    @Test
    fun manualPairing_duplicateMacCommitment_abortsWithoutPinning() =
        runTest {
            val rig = Rig(this)
            rig.start()
            rig.session.emitIncoming(challengeEnvelope())
            runCurrent()
            rig.session.emitIncoming(macCommitmentEnvelope())
            rig.session.emitIncoming(macCommitmentEnvelope())
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ProtocolViolation), rig.machine.state.value)
            assertTrue(rig.committer.commits.isEmpty())
        }

    @Test
    fun manualPairing_macLeafNotP256_failsClosedAsIncompatibleKeyNotUnreachable() =
        runTest {
            val machine =
                ManualPairingStateMachine(
                    TestClock(testScheduler),
                    StandardTestDispatcher(testScheduler),
                    { _, _ -> throw java.security.cert.CertificateException("pinned peer mismatch") },
                    RecordingCommitter(),
                    address,
                    { noncePhone },
                )

            machine.start()
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.IncompatibleMacKey), machine.state.value)
        }

    @Test
    fun manualPairingAddress_literalIpAndPort_parsed() {
        assertEquals("192.168.1.10", ManualPairingAddress.parse("192.168.1.10:62747")?.host)
        assertEquals(62747, ManualPairingAddress.parse(" 192.168.1.10:62747 ")?.port)
        assertEquals("fe80::1", ManualPairingAddress.parse("[fe80::1]:1234")?.host)
    }

    @Test
    fun manualPairingAddress_hostnamesZonesAndBadPorts_rejected() {
        assertNull(ManualPairingAddress.parse("mac.local:62747"))
        assertNull(ManualPairingAddress.parse("192.168.1.10"))
        assertNull(ManualPairingAddress.parse("192.168.1.10:0"))
        assertNull(ManualPairingAddress.parse("192.168.1.10:70000"))
        assertNull(ManualPairingAddress.parse("[fe80::1%en0]:1234"))
        assertNull(ManualPairingAddress.parse("fe80::1:1234"))
        assertNull(ManualPairingAddress.parse("0.0.0.0:1234"))
        assertNotNull(ManualPairingAddress.parse("10.0.0.1:1"))
    }

    private inner class Rig(
        private val testScope: TestScope,
    ) {
        val session = FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }
        val committer = RecordingCommitter()
        val machine =
            ManualPairingStateMachine(
                TestClock(testScope.testScheduler),
                StandardTestDispatcher(testScope.testScheduler),
                { _, _ -> PairingConnection(session, macSpkiDer, phoneSpkiDer) },
                committer,
                address,
                { noncePhone },
            )

        fun start() {
            machine.start()
            testScope.runCurrent()
        }

        fun sentCases(): List<Envelope.PayloadCase> = session.sentFrames.map { it.payloadCase }

        fun reachSasOnScreen() {
            start()
            session.emitIncoming(challengeEnvelope())
            testScope.runCurrent()
            session.emitIncoming(macCommitmentEnvelope())
            testScope.runCurrent()
            session.emitIncoming(revealEnvelope(nonceMac))
            testScope.runCurrent()
        }
    }

    private class RecordingCommitter : TrustCommitter {
        val commits = mutableListOf<SpkiFingerprint>()

        override suspend fun commit(
            fingerprint: SpkiFingerprint,
            macName: String,
            pairedAt: Instant,
        ) {
            commits += fingerprint
        }
    }

    private fun challengeEnvelope(): Envelope =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            val cb = ByteString.copyFrom(challenge)
            pairChallenge = pairChallenge { this.challenge = cb }
        }

    private fun macCommitmentEnvelope(): Envelope {
        val hash = ManualPairingSas.commitment(ManualPairingSas.Role.MAC, nonceMac, context)
        return envelope {
            channel = Channel.CHANNEL_CONTROL
            commitment = commitment { this.hash = ByteString.copyFrom(hash) }
        }
    }

    private fun revealEnvelope(nonce: ByteArray): Envelope =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            reveal = reveal { this.nonce = ByteString.copyFrom(nonce) }
        }

    private fun manualPairResult(accepted: Boolean): Envelope =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            manualPairResult = manualPairResult { this.accepted = accepted }
        }

    private fun hexToBytes(hex: String): ByteArray =
        ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}
