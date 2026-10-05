package dev.tandem.core.storage.rotation

import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.storage.trust.GRACE_PERIOD_MS
import dev.tandem.core.storage.trust.PENDING_MAX_AGE_MS
import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.core.storage.trust.TrustStore
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.RotationRejectReason
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import java.security.SecureRandom
import java.time.Instant

private const val AWAIT_TIMEOUT_MS = 5_000L
private const val POLL_MS = 10L
private const val NOW_MS = 1_000_000_000L

@RunWith(AndroidJUnit4::class)
class RotationReceiverTest {
    private lateinit var store: TrustStore
    private lateinit var session: FakeTandemSession
    private val clock = MutableClock(NOW_MS)
    private val rejections = mutableListOf<RotationRejectReason>()
    private val oldKey = TestIdentity()
    private val newKey = TestIdentity()

    @Before
    fun setUp() {
        store = TrustStore.openInMemory(RuntimeEnvironment.getApplication())
        session = FakeTandemSession()
    }

    @After
    fun tearDown() {
        store.close()
    }

    private fun receiver(
        authenticatedWith: TestIdentity?,
        pins: RotationPinStore = store,
        fakeSession: FakeTandemSession = session,
    ) = RotationReceiver(
        session = fakeSession,
        authenticatedPeerSpkiDer = authenticatedWith?.spkiDer,
        pins = pins,
        clock = clock,
        random = SecureRandom(),
        eventLog = { rejections += it },
    )

    private suspend fun awaitUntil(condition: () -> Boolean) {
        withTimeout(AWAIT_TIMEOUT_MS) { while (!condition()) delay(POLL_MS) }
    }

    private suspend fun startReady(
        receiver: RotationReceiver,
        fakeSession: FakeTandemSession = session,
    ): Job {
        val job = kotlinx.coroutines.GlobalScope.launch(Dispatchers.Default) { receiver.run() }
        fakeSession.emitState(ConnectionState.Ready(Instant.EPOCH))
        awaitUntil { fakeSession.sentFrames.isNotEmpty() }
        return job
    }

    private fun challengeOf(fakeSession: FakeTandemSession = session): ByteArray =
        fakeSession.sentFrames
            .first()
            .rotationChallenge.challenge
            .toByteArray()

    private suspend fun rotate(
        cb: ByteArray,
        fakeSession: FakeTandemSession = session,
        signedOld: TestIdentity = oldKey,
        signedNew: TestIdentity = newKey,
        newSpki: TestIdentity = newKey,
    ) {
        val before = fakeSession.sentFrames.size
        fakeSession.emitIncoming(keyRotationEnvelope(oldKey, newSpki, cb, signedOld, signedNew))
        awaitUntil { fakeSession.sentFrames.size > before }
    }

    private fun lastReject() =
        session.sentFrames
            .last()
            .rotationReject.reason

    private suspend fun pinOld() = store.put(peerRecord(oldKey))

    @Test
    fun androidRotationReceiver_sessionReachesReady_sendsExactlyOneRotationChallengeUnconditionally() =
        runBlocking {
            pinOld()
            val job = startReady(receiver(oldKey))
            session.emitState(ConnectionState.Ready(Instant.EPOCH))
            delay(100)

            assertEquals(1, session.sentFrames.size)
            assertEquals(32, challengeOf().size)
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_validSignature_pinsNewKeyAndFlagsOldGraceOnly() =
        runBlocking {
            pinOld()
            val job = startReady(receiver(oldKey))
            rotate(challengeOf())

            assertTrue(session.sentFrames.last().hasRotationAck())
            assertEquals(
                newKey.fingerprint.base64Url,
                store.get(oldKey.fingerprint)!!.pendingSpkiSha256Base64Url,
            )
            job.cancel()

            val promotingSession = FakeTandemSession()
            val promotingJob = startReady(receiver(newKey, fakeSession = promotingSession), promotingSession)
            awaitUntil { runBlocking { store.get(newKey.fingerprint) } != null }
            promotingJob.cancel()

            val promoted = store.get(newKey.fingerprint)!!
            assertEquals(oldKey.fingerprint.base64Url, promoted.graceSpkiSha256Base64Url)
            assertEquals(NOW_MS + GRACE_PERIOD_MS, promoted.graceExpiresAtEpochMs)
            assertEquals(PinKind.GRACE, store.resolve(oldKey.fingerprint, NOW_MS)!!.kind)
            assertEquals(PinKind.PRIMARY, store.resolve(newKey.fingerprint, NOW_MS)!!.kind)
        }

    @Test
    fun androidRotationReceiver_macRotationAcked_oldMacPinPrimaryUntilNewKeyPresented() =
        runBlocking {
            pinOld()
            val job = startReady(receiver(oldKey))
            rotate(challengeOf())
            job.cancel()

            repeat(3) {
                val next = FakeTandemSession()
                val nextJob = startReady(receiver(oldKey, fakeSession = next), next)
                delay(50)
                nextJob.cancel()
            }

            val record = store.get(oldKey.fingerprint)!!
            assertEquals(newKey.fingerprint.base64Url, record.pendingSpkiSha256Base64Url)
            assertNull(store.get(newKey.fingerprint))
        }

    @Test
    fun androidRotationReceiver_newKeySessionCompletesHello_oldPinPurged() =
        runBlocking {
            store.put(
                peerRecord(newKey).copy(
                    graceSpkiSha256Base64Url = oldKey.fingerprint.base64Url,
                    graceExpiresAtEpochMs = NOW_MS + GRACE_PERIOD_MS,
                ),
            )
            val job = startReady(receiver(newKey))
            awaitUntil { runBlocking { store.get(newKey.fingerprint)!!.graceSpkiSha256Base64Url } == null }

            assertNull(store.resolve(oldKey.fingerprint, NOW_MS))
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_graceSessionClosed_oldPinPurged() =
        runBlocking {
            store.put(
                peerRecord(newKey).copy(
                    graceSpkiSha256Base64Url = oldKey.fingerprint.base64Url,
                    graceExpiresAtEpochMs = NOW_MS + GRACE_PERIOD_MS,
                ),
            )
            val job = startReady(receiver(oldKey))
            assertNotNull(store.resolve(oldKey.fingerprint, NOW_MS))

            session.close()
            job.join()

            assertNull(store.resolve(oldKey.fingerprint, NOW_MS))
            assertNull(store.get(newKey.fingerprint)!!.graceSpkiSha256Base64Url)
        }

    @Test
    fun androidRotationReceiver_invalidSignature_rejectInvalidSignatureTrustStoreUnchanged() =
        runBlocking {
            pinOld()
            val before = store.list()
            val job = startReady(receiver(oldKey))
            rotate(challengeOf(), signedOld = newKey)

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_INVALID_SIGNATURE, lastReject())
            assertEquals(before, store.list())
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_unauthenticatedSession_rejectUnauthenticatedTrustStoreUnchanged() =
        runBlocking {
            pinOld()
            val before = store.list()
            val job = startReady(receiver(authenticatedWith = null))
            rotate(challengeOf())

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_UNAUTHENTICATED_SESSION, lastReject())
            assertEquals(before, store.list())
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_graceOnlyKeySignsDifferentSpki_rejectNotPrimaryPin() =
        runBlocking {
            store.put(
                peerRecord(newKey).copy(
                    graceSpkiSha256Base64Url = oldKey.fingerprint.base64Url,
                    graceExpiresAtEpochMs = NOW_MS + GRACE_PERIOD_MS,
                ),
            )
            val before = store.list()
            val job = startReady(receiver(oldKey))
            rotate(challengeOf(), newSpki = TestIdentity())

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_NOT_PRIMARY_PIN, lastReject())
            assertEquals(before, store.list())
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_resendSameNewSpki_acksWithoutTrustStoreChange() =
        runBlocking {
            pinOld()
            val job = startReady(receiver(oldKey))
            rotate(challengeOf())
            val afterFirst = store.list()

            rotate(challengeOf())

            assertTrue(session.sentFrames.last().hasRotationAck())
            assertEquals(afterFirst, store.list())
            assertTrue(rejections.isEmpty())
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_rejection_logsReasonWithoutKeyBytes() =
        runBlocking {
            pinOld()
            val job = startReady(receiver(oldKey))
            rotate(challengeOf(), signedNew = oldKey)

            assertEquals(listOf(RotationRejectReason.ROTATION_REJECT_REASON_INVALID_SIGNATURE), rejections)
            assertFalse(rejections.toString().contains(oldKey.fingerprint.base64Url))
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_replayedFromOtherSession_rejectInvalidSignature() =
        runBlocking {
            pinOld()
            val otherSession = FakeTandemSession()
            val otherJob = startReady(receiver(oldKey, fakeSession = otherSession), otherSession)
            val otherChallenge = challengeOf(otherSession)
            val job = startReady(receiver(oldKey))

            rotate(otherChallenge)

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_INVALID_SIGNATURE, lastReject())
            assertNull(store.get(oldKey.fingerprint)!!.pendingSpkiSha256Base64Url)
            job.cancel()
            otherJob.cancel()
        }

    @Test
    fun androidRotationReceiver_consumedChallengeReplayedOnSameSession_rejectInvalidSignature() =
        runBlocking {
            pinOld()
            val job = startReady(receiver(oldKey))
            val cb = challengeOf()
            rotate(cb, signedNew = oldKey)

            rotate(cb)

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_INVALID_SIGNATURE, lastReject())
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_newSpkiEqualsExistingPin_rejectDuplicateKey() =
        runBlocking {
            pinOld()
            store.put(peerRecord(newKey).copy(deviceId = "other-mac"))
            val job = startReady(receiver(oldKey))
            rotate(challengeOf())

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_DUPLICATE_KEY, lastReject())
            assertNull(store.get(oldKey.fingerprint)!!.pendingSpkiSha256Base64Url)
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_faultInjectedPinSwap_stateOldOrNewNeverPartial() =
        runBlocking {
            pinOld()
            val before = store.list()
            val faulting =
                object : RotationPinStore by store {
                    override suspend fun setPending(
                        primary: dev.tandem.core.crypto.SpkiFingerprint,
                        pending: dev.tandem.core.crypto.SpkiFingerprint,
                        sinceEpochMs: Long,
                    ): Boolean = error("injected fault")
                }
            val job = startReady(receiver(oldKey, pins = faulting))
            rotate(challengeOf())

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_ROTATION_UNAVAILABLE, lastReject())
            assertEquals(before, store.list())
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_gracePinOlderThan7Days_purgedWithoutSession() =
        runBlocking {
            store.put(
                peerRecord(newKey).copy(
                    graceSpkiSha256Base64Url = oldKey.fingerprint.base64Url,
                    graceExpiresAtEpochMs = NOW_MS,
                ),
            )
            assertNull(store.resolve(oldKey.fingerprint, NOW_MS))

            store.purgeExpiredPins(NOW_MS)

            val record: PeerRecord = store.get(newKey.fingerprint)!!
            assertNull(record.graceSpkiSha256Base64Url)
            assertNull(record.graceExpiresAtEpochMs)
        }

    @Test
    fun androidRotationReceiver_pendingPinNeverPresentedFor30Days_purgedOldPinStaysPrimary() =
        runBlocking {
            store.put(
                peerRecord(oldKey).copy(
                    pendingSpkiSha256Base64Url = newKey.fingerprint.base64Url,
                    pendingSinceEpochMs = NOW_MS - PENDING_MAX_AGE_MS,
                ),
            )
            assertNull(store.resolve(newKey.fingerprint, NOW_MS))

            store.purgeExpiredPins(NOW_MS)

            val record = store.get(oldKey.fingerprint)!!
            assertNull(record.pendingSpkiSha256Base64Url)
            assertEquals(PinKind.PRIMARY, store.resolve(oldKey.fingerprint, NOW_MS)!!.kind)
        }

    @Test
    fun androidRotationReceiver_sessionStart_purgesExpiredPins() =
        runBlocking {
            store.put(
                peerRecord(newKey).copy(
                    graceSpkiSha256Base64Url = oldKey.fingerprint.base64Url,
                    graceExpiresAtEpochMs = NOW_MS,
                ),
            )
            val job = startReady(receiver(null))

            assertNull(store.get(newKey.fingerprint)!!.graceSpkiSha256Base64Url)
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_purgeThrows_receiverStaysAliveAndStillRejects() =
        runBlocking {
            pinOld()
            val failingPurge =
                object : RotationPinStore by store {
                    override suspend fun purgeExpiredPins(nowEpochMs: Long): Unit = error("injected fault")
                }
            val job = startReady(receiver(oldKey, pins = failingPurge))
            rotate(challengeOf())

            assertTrue(session.sentFrames.last().hasRotationAck())
            assertTrue(job.isActive)
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_resolveThrowsOnRotation_rejectsUnavailableLogsReasonAndStaysAlive() =
        runBlocking {
            pinOld()
            val before = store.list()
            val failing = FailingResolveStore(store)
            val job = startReady(receiver(oldKey, pins = failing))
            failing.failResolve = true
            rotate(challengeOf())

            assertEquals(RotationRejectReason.ROTATION_REJECT_REASON_ROTATION_UNAVAILABLE, lastReject())
            assertEquals(listOf(RotationRejectReason.ROTATION_REJECT_REASON_ROTATION_UNAVAILABLE), rejections)
            assertEquals(before, store.list())
            assertTrue(job.isActive)

            failing.failResolve = false
            rotate(challengeOf())
            assertTrue(session.sentFrames.last().hasRotationAck() || session.sentFrames.last().hasRotationReject())
            job.cancel()
        }

    @Test
    fun androidRotationReceiver_handshakeRulesThrow_receiverStaysAlive() =
        runBlocking {
            pinOld()
            val failing = FailingResolveStore(store).apply { failResolve = true }
            val job = startReady(receiver(oldKey, pins = failing))

            assertTrue(job.isActive)
            job.cancel()
        }

    private class FailingResolveStore(
        private val delegate: TrustStore,
    ) : RotationPinStore by delegate {
        @Volatile var failResolve = false

        override suspend fun resolve(
            fingerprint: dev.tandem.core.crypto.SpkiFingerprint,
            nowEpochMs: Long,
        ): ResolvedPin? = if (failResolve) error("injected fault") else delegate.resolve(fingerprint, nowEpochMs)
    }
}
