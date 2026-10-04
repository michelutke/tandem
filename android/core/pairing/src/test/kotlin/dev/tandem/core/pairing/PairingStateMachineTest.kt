package dev.tandem.core.pairing

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ConfirmationCode
import dev.tandem.core.crypto.PairingProof
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.SpkiFingerprint
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
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.cert.CertificateException
import java.time.Instant

/**
 * PairingStateMachine tests (E14-05; `docs/planning/backlog/phase-1.yaml` E14-05's `tdd:` list).
 * Every machine here is built from a `TestClock`/`StandardTestDispatcher` pair sharing one
 * `TestCoroutineScheduler`, so its 3 s per-address dial (D-68) and 120 s waits (SPEC.md §2) advance
 * in virtual time under `runTest` (E00-18); [FakePairingConnector] never opens a real socket, and
 * hands back a [FakeTandemSession] (E12-11 testFixtures) whenever it "connects".
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PairingStateMachineTest {
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
    private val secret = hexToBytes("c00cfdcf0eafd84361794f980a688157")
    private val challenge =
        hexToBytes("83f7523553c91d478b4a6809c3864afc28d8b061bcaa6e5c148509b6cc2caa96")
    private val fingerprint = ByteArray(32) { it.toByte() }

    private val invite =
        PairingInvite(
            fingerprint = fingerprint,
            secret = secret,
            addresses = listOf("192.168.1.1", "192.168.1.2"),
            port = 8443,
            macName = "Study Mac",
        )

    @Test
    fun pairingSm_startPairingFromIdle_emitsConnecting() =
        runTest {
            val sm = newMachine(FakePairingConnector(emptyMap()))

            assertEquals(PairingState.Idle, sm.state.value)
            sm.start()
            assertEquals(PairingState.Connecting, sm.state.value)
        }

    @Test
    fun pairingSm_firstAddressTimesOut_dialsNextQrAddress() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[1] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            advanceTimeBy(PairingStateMachine.CONNECT_TIMEOUT)
            runCurrent()

            assertEquals(listOf(invite.addresses[0], invite.addresses[1]), connector.attempted)
            assertEquals(PairingState.AwaitingProofSent, sm.state.value)
        }

    @Test
    fun pairingSm_allQrAddressesTimeOut_emitsFailedAllAddressesUnreachable() =
        runTest {
            val connector = FakePairingConnector(emptyMap())
            val sm = newMachine(connector)

            sm.start()
            repeat(invite.addresses.size) {
                advanceTimeBy(PairingStateMachine.CONNECT_TIMEOUT)
                runCurrent()
            }

            assertEquals(listOf(invite.addresses[0], invite.addresses[1]), connector.attempted)
            assertEquals(PairingState.Failed(PairingFailure.AllAddressesUnreachable), sm.state.value)
        }

    @Test
    fun pairingSm_firstAddressConnectThrows_dialsNextQrAddressInsteadOfCrashing() =
        runTest {
            val session = readySession()
            val connector =
                FakePairingConnector(
                    mapOf(invite.addresses[1] to connectionOf(session)),
                    failing = setOf(invite.addresses[0]),
                )
            val sm = newMachine(connector)

            sm.start()
            runCurrent()

            assertEquals(listOf(invite.addresses[0], invite.addresses[1]), connector.attempted)
            assertEquals(PairingState.AwaitingProofSent, sm.state.value)
        }

    @Test
    fun pairingSm_everyAddressConnectThrows_emitsFailedAllAddressesUnreachable() =
        runTest {
            val connector =
                FakePairingConnector(emptyMap(), failing = setOf(invite.addresses[0], invite.addresses[1]))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.AllAddressesUnreachable), sm.state.value)
        }

    @Test
    fun pairingSm_pinMismatchOnAnyAddress_emitsFailedPinMismatch() =
        runTest {
            val connector =
                FakePairingConnector(
                    emptyMap(),
                    failing = setOf(invite.addresses[1]),
                    pinMismatching = setOf(invite.addresses[0]),
                )
            val sm = newMachine(connector)

            sm.start()
            runCurrent()

            assertEquals(listOf(invite.addresses[0], invite.addresses[1]), connector.attempted)
            assertEquals(PairingState.Failed(PairingFailure.PinMismatch), sm.state.value)
        }

    @Test
    fun pairingSm_confirmCodesMatch_closesPairingSessionAfterCommit() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            session.emitIncoming(pairAcceptedEnvelope())
            runCurrent()

            sm.confirmCodesMatch()
            runCurrent()

            assertEquals(PairingState.Paired, sm.state.value)
            assertTrue(session.state.value is ConnectionState.Disconnected)
        }

    @Test
    fun pairingSm_tlsReady_sendsPairRequestAndEmitsAwaitingAccept() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            assertEquals(PairingState.AwaitingProofSent, sm.state.value)

            session.emitIncoming(challengeEnvelope())
            runCurrent()

            val expectedCode = ConfirmationCode.compute(secret, macSpkiDer, phoneSpkiDer, challenge)
            assertEquals(PairingState.AwaitingAccept(expectedCode), sm.state.value)

            val expectedProof = PairingProof.compute(secret, macSpkiDer, phoneSpkiDer, challenge)
            val sentRequest = session.sentFrames.single().pairRequest
            assertEquals(expectedProof.toList(), sentRequest.proof.toByteArray().toList())
        }

    @Test
    fun pairingSm_malformedPairChallenge_emitsFailedMalformedChallengeInsteadOfCrashing() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()

            val notThirtyTwoBytes = ByteString.copyFrom(ByteArray(4))
            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTROL
                    pairChallenge = pairChallenge { this.challenge = notThirtyTwoBytes }
                },
            )
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.MalformedChallenge), sm.state.value)
        }

    @Test
    fun pairingSm_userConfirmsCodes_commitsMacFingerprintAndEmitsPaired() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val trustCommitter = FakeTrustCommitter()
            val sm = newMachine(connector, trustCommitter)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            session.emitIncoming(pairAcceptedEnvelope())
            runCurrent()
            assertTrue(sm.state.value is PairingState.AwaitingUserConfirm)

            sm.confirmCodesMatch()

            assertEquals(PairingState.Paired, sm.state.value)
            assertEquals(1, trustCommitter.commits.size)
            val commit = trustCommitter.commits.single()
            assertEquals(SpkiFingerprint(fingerprint).base64Url, commit.fingerprint.base64Url)
            assertEquals(invite.macName, commit.macName)
        }

    @Test
    fun pairingSm_pairRejectedReceived_emitsRejectedTrustStoreUnchanged() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val trustCommitter = FakeTrustCommitter()
            val sm = newMachine(connector, trustCommitter)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            session.emitIncoming(pairRejectedEnvelope(PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER))
            runCurrent()

            assertEquals(
                PairingState.Rejected(PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER),
                sm.state.value,
            )
            assertTrue(trustCommitter.commits.isEmpty())
        }

    @Test
    fun pairingSm_noResponseWithin120s_emitsFailedTimeout() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            assertTrue(sm.state.value is PairingState.AwaitingAccept)

            advanceTimeBy(PairingStateMachine.ACCEPT_TIMEOUT)
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.Timeout), sm.state.value)
        }

    @Test
    fun pairingSm_sessionDropsWhileAwaiting_emitsFailedConnectionLost() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            assertTrue(sm.state.value is PairingState.AwaitingAccept)

            session.emitState(ConnectionState.Disconnected("peer closed the connection"))
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ConnectionLost), sm.state.value)
        }

    @Test
    fun pairingSm_pairAcceptedReceived_emitsAwaitingUserConfirmWithCode() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            val expectedCode = ConfirmationCode.compute(secret, macSpkiDer, phoneSpkiDer, challenge)

            session.emitIncoming(pairAcceptedEnvelope())
            runCurrent()

            assertEquals(PairingState.AwaitingUserConfirm(expectedCode, invite.macName), sm.state.value)
        }

    @Test
    fun pairingSm_userCancelsCodeConfirm_sendsRevokeTrustStoreUnchanged() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val trustCommitter = FakeTrustCommitter()
            val sm = newMachine(connector, trustCommitter)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            session.emitIncoming(pairAcceptedEnvelope())
            runCurrent()

            sm.cancelConfirm()
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.UserCancelled), sm.state.value)
            assertTrue(trustCommitter.commits.isEmpty())
            assertTrue(session.sentFrames.any { it.payloadCase == Envelope.PayloadCase.REVOKE })
        }

    @Test
    fun pairingSm_codeConfirmUnansweredFor120s_sendsRevokeTrustStoreUnchanged() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val trustCommitter = FakeTrustCommitter()
            val sm = newMachine(connector, trustCommitter)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            session.emitIncoming(pairAcceptedEnvelope())
            runCurrent()

            advanceTimeBy(PairingStateMachine.CONFIRM_TIMEOUT)
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ConfirmationTimeout), sm.state.value)
            assertTrue(trustCommitter.commits.isEmpty())
            assertTrue(session.sentFrames.any { it.payloadCase == Envelope.PayloadCase.REVOKE })
        }

    @Test
    fun pairingSm_confirmRacesDeadlineAtBoundary_exactlyOneOutcomeWins() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val trustCommitter = FakeTrustCommitter()
            val sm = newMachine(connector, trustCommitter)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            session.emitIncoming(pairAcceptedEnvelope())
            runCurrent()

            advanceTimeBy(PairingStateMachine.CONFIRM_TIMEOUT)
            launch { sm.confirmCodesMatch() }
            runCurrent()

            val state = sm.state.value
            assertTrue(state == PairingState.Paired || state == PairingState.Failed(PairingFailure.ConfirmationTimeout))
            val committed = state == PairingState.Paired
            assertEquals(if (committed) 1 else 0, trustCommitter.commits.size)
            assertEquals(!committed, session.sentFrames.any { it.payloadCase == Envelope.PayloadCase.REVOKE })
        }

    @Test
    fun pairingSm_awaitingAccept_exposesConfirmationCodeBeforePairAccepted() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()

            val awaitingAccept = sm.state.value as PairingState.AwaitingAccept
            val expectedCode = ConfirmationCode.compute(secret, macSpkiDer, phoneSpkiDer, challenge)
            assertEquals(expectedCode, awaitingAccept.code)
        }

    @Test
    fun pairingSm_noPairChallengeWithin10s_emitsFailedChallengeTimeout() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            assertEquals(PairingState.AwaitingProofSent, sm.state.value)

            advanceTimeBy(PairingStateMachine.CHALLENGE_TIMEOUT)
            runCurrent()

            assertEquals(PairingState.Failed(PairingFailure.ChallengeTimeout), sm.state.value)
        }

    @Test
    fun pairingSm_closeWhileAwaitingUserConfirm_sendsRevoke() =
        runTest {
            val session = readySession()
            val connector = FakePairingConnector(mapOf(invite.addresses[0] to connectionOf(session)))
            val sm = newMachine(connector)

            sm.start()
            runCurrent()
            session.emitIncoming(challengeEnvelope())
            runCurrent()
            session.emitIncoming(pairAcceptedEnvelope())
            runCurrent()
            assertTrue(sm.state.value is PairingState.AwaitingUserConfirm)

            sm.close()
            runCurrent()

            assertTrue(session.sentFrames.any { it.payloadCase == Envelope.PayloadCase.REVOKE })
        }

    private fun TestScope.newMachine(
        connector: PairingConnector,
        trustCommitter: TrustCommitter = FakeTrustCommitter(),
    ): PairingStateMachine =
        PairingStateMachine(
            TestClock(testScheduler),
            StandardTestDispatcher(testScheduler),
            connector,
            trustCommitter,
            invite,
            FakeDeviceInfoProvider(),
        )

    private fun readySession(): FakeTandemSession =
        FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }

    private fun connectionOf(session: FakeTandemSession): PairingConnection =
        PairingConnection(session, macSpkiDer, phoneSpkiDer)

    private fun challengeEnvelope(): Envelope {
        val challengeBytes = ByteString.copyFrom(challenge)
        return envelope {
            channel = Channel.CHANNEL_CONTROL
            pairChallenge = pairChallenge { this.challenge = challengeBytes }
        }
    }

    private fun pairAcceptedEnvelope(): Envelope =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            pairAccepted = pairAccepted {}
        }

    private fun pairRejectedEnvelope(reason: PairRejectedReason): Envelope =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            pairRejected = pairRejected { this.reason = reason }
        }

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "Hex string must have even length" }
        return ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }

    private class FakePairingConnector(
        private val responses: Map<String, PairingConnection>,
        private val failing: Set<String> = emptySet(),
        private val pinMismatching: Set<String> = emptySet(),
    ) : PairingConnector {
        val attempted = mutableListOf<String>()

        override suspend fun connect(
            address: String,
            port: Int,
            pinSource: PinSource,
        ): PairingConnection {
            attempted += address
            if (address in failing) error("connection refused")
            if (address in pinMismatching) throw CertificateException("pin mismatch")
            return responses[address] ?: awaitCancellation()
        }
    }

    private class FakeTrustCommitter : TrustCommitter {
        val commits = mutableListOf<Commit>()

        override suspend fun commit(
            fingerprint: SpkiFingerprint,
            macName: String,
            pairedAt: Instant,
        ) {
            commits += Commit(fingerprint, macName, pairedAt)
        }

        class Commit(
            val fingerprint: SpkiFingerprint,
            val macName: String,
            val pairedAt: Instant,
        )
    }

    private class FakeDeviceInfoProvider(
        private val name: String = "Test Phone",
        private val model: String = "Pixel 8",
    ) : DeviceInfoProvider {
        override fun displayName(): String = name

        override fun model(): String = model
    }
}
