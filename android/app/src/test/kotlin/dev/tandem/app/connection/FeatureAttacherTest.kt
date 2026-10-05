package dev.tandem.app.connection

import dev.tandem.app.service.RegisteredSession
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.TandemSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class FeatureAttacherTest {
    private val peer = SpkiFingerprint(ByteArray(32) { 6 })

    @Test
    fun featureAttacher_oneFeatureThrows_otherFeaturesStayAttachedUntilClose() =
        runTest(UnconfinedTestDispatcher()) {
            val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
            val failures = mutableListOf<Throwable>()
            var healthyDetached = false
            val attacher =
                FeatureAttacher(
                    listOf(
                        SessionFeature { _, _, _ -> error("boom") },
                        object : SessionFeature {
                            override suspend fun run(
                                session: TandemSession,
                                peer: SpkiFingerprint,
                                peerSpkiDer: ByteArray?,
                            ) {
                                try {
                                    awaitCancellation()
                                } finally {
                                    healthyDetached = true
                                }
                            }
                        },
                    ),
                    failures::add,
                )

            val attached = launch { attacher.attach(RegisteredSession(session, peer)) }
            assertEquals(1, failures.size)
            assertTrue(!healthyDetached)

            session.close()

            assertTrue(attached.isCompleted)
            assertTrue(healthyDetached)
        }

    @Test
    fun featureAttacher_sessionReady_allRemainingConsumersAttachedOnce() =
        runTest(UnconfinedTestDispatcher()) {
            val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
            val consumers = REMAINING_CONSUMERS.map { CountingFeature(it) }
            val attacher = FeatureAttacher(consumers, {})

            val attached = launch { attacher.attach(RegisteredSession(session, peer, peerDer)) }

            consumers.forEach {
                assertEquals(1, it.attached, it.name)
                assertEquals(0, it.detached, it.name)
                assertEquals(peerDer, it.peerSpkiDer, it.name)
            }
            session.close()
            assertTrue(attached.isCompleted)
        }

    @Test
    fun featureAttacher_sessionClosed_allRemainingConsumersDetached() =
        runTest(UnconfinedTestDispatcher()) {
            val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
            val consumers = REMAINING_CONSUMERS.map { CountingFeature(it) }
            val attacher = FeatureAttacher(consumers, {})
            launch { attacher.attach(RegisteredSession(session, peer, peerDer)) }

            session.close()

            consumers.forEach {
                assertEquals(1, it.detached, it.name)
                assertEquals(1, it.attached, it.name)
            }
        }

    private class CountingFeature(
        val name: String,
    ) : SessionFeature {
        var attached = 0
        var detached = 0
        var peerSpkiDer: ByteArray? = null

        override suspend fun run(
            session: TandemSession,
            peer: SpkiFingerprint,
            peerSpkiDer: ByteArray?,
        ) {
            attached++
            this.peerSpkiDer = peerSpkiDer
            try {
                awaitCancellation()
            } finally {
                detached++
            }
        }
    }

    private companion object {
        val peerDer = ByteArray(4) { 9 }
        val REMAINING_CONSUMERS =
            listOf(
                "contacts",
                "sms",
                "status",
                "focus",
                "notificationActions",
                "rotation",
            )
    }
}
