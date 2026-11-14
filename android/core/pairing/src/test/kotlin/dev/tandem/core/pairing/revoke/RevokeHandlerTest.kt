package dev.tandem.core.pairing.revoke

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.PeerDataPurgeRegistry
import dev.tandem.core.pairing.PeerDataPurging
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

class RevokeHandlerTest {
    private val peer = SpkiFingerprint(ByteArray(FINGERPRINT_BYTES) { 7 })
    private val removed = mutableListOf<SpkiFingerprint>()
    private val purged = mutableListOf<SpkiFingerprint>()
    private val session = FakeTandemSession()
    private val purgeRegistry =
        PeerDataPurgeRegistry().apply {
            register(
                PeerDataPurging { fingerprint ->
                    assertTrue(session.state.value is ConnectionState.Disconnected, "purge after close")
                    purged += fingerprint
                },
            )
        }
    private val handler =
        RevokeHandler(
            session,
            peer,
            { fingerprint ->
                assertTrue(session.state.value is ConnectionState.Ready, "trust removed before close")
                removed += fingerprint
            },
            purgeRegistry,
        )

    @Test
    fun revokeHandler_revokeOnReadySession_deletesMacRecordAndCloses() =
        runTest {
            session.emitState(ConnectionState.Ready(Instant.EPOCH))

            assertTrue(handler.handleRevoke())

            assertEquals(listOf(peer), removed)
            assertTrue(session.state.value is ConnectionState.Disconnected)
        }

    @Test
    fun revokeHandler_revokeOnReadySession_purgesPeerDataAfterClose() =
        runTest {
            session.emitState(ConnectionState.Ready(Instant.EPOCH))

            handler.handleRevoke()

            assertEquals(listOf(peer), purged)
        }

    @Test
    fun revokeHandler_revokeBeforeReady_ignoredTrustStoreUnchanged() =
        runTest {
            session.emitState(ConnectionState.HelloExchange)

            assertFalse(handler.handleRevoke())

            assertTrue(removed.isEmpty())
            assertTrue(purged.isEmpty())
            assertEquals(ConnectionState.HelloExchange, session.state.value)
        }

    @Test
    fun revokeHandler_callerCancelledAfterSessionClose_stillPurges() =
        runTest {
            session.emitState(ConnectionState.Ready(Instant.EPOCH))
            val noticed = mutableListOf<SpkiFingerprint>()
            lateinit var caller: Job
            val registry =
                PeerDataPurgeRegistry().apply {
                    register(
                        PeerDataPurging { fingerprint ->
                            yield()
                            purged += fingerprint
                        },
                    )
                }
            val cancellingHandler =
                RevokeHandler(
                    session,
                    peer,
                    { fingerprint ->
                        noticed += fingerprint
                        caller.cancel()
                    },
                    registry,
                )

            caller = launch { cancellingHandler.handleRevoke() }
            caller.join()

            assertEquals(listOf(peer), noticed)
            assertEquals(listOf(peer), purged)
            assertTrue(session.state.value is ConnectionState.Disconnected)
        }

    private companion object {
        const val FINGERPRINT_BYTES = 32
    }
}
