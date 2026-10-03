package dev.tandem.app.connection

import dev.tandem.app.connection.feature.NotificationsFeature
import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.discovery.DiscoveryEvent
import dev.tandem.core.discovery.PairedMacMatcher
import dev.tandem.core.discovery.ServiceDiscovery
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.reconnect.NetworkMonitor
import dev.tandem.core.transport.reconnect.PairedMacBonjourSource
import dev.tandem.core.transport.reconnect.PairingAddressSource
import dev.tandem.feature.notifications.LiveNotificationEventSink
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.notificationPosted
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Clock

// integration: tandemServiceComposition_jvmLoopbackMac_readyAndNotificationFlows
//
// In-process loopback: the "Mac" is a second real ByteStreamSession on the far end of an
// InMemoryDuplexPipe, so the real handshake, multiplexer and NotificationSink run end to end. TLS
// and pinning are covered by core/crypto and core/transport's own tests; the dialer is faked here.
class ConnectionLoopbackTest {
    @Test
    fun tandemServiceComposition_jvmLoopbackMac_readyAndNotificationFlows(
        @TempDir directory: File,
    ) = runBlocking(Dispatchers.IO) {
        val pipe = InMemoryDuplexPipe()
        val peer = SpkiFingerprint(ByteArray(32) { 9 })
        val mac = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)
        val registry = SessionRegistry()
        val orchestrator =
            ConnectionOrchestrator(
                dialer =
                    SessionDialer {
                        DialResult.Connected(ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO), peer)
                    },
                registry = registry,
                featureAttacher =
                    FeatureAttacher(listOf(NotificationsFeature({ 0L }, Clock.systemUTC(), Dispatchers.IO))) {},
                knownPeerStore = KnownPeerStore(File(directory, "known-peers")),
                bonjourSource =
                    PairedMacBonjourSource(
                        object : ServiceDiscovery {
                            override fun browse(): Flow<DiscoveryEvent> = emptyFlow()
                        },
                        PairedMacMatcher(Clock.systemUTC()),
                        { emptyList() },
                        Dispatchers.IO,
                    ),
                pairingAddressSource = PairingAddressSource { listOf(CandidateAddress("192.0.2.1", 7000)) },
                networkMonitor =
                    object : NetworkMonitor {
                        override val available: Flow<Unit> = emptyFlow()
                    },
                clock = Clock.systemUTC(),
                dispatcher = Dispatchers.IO,
            )

        try {
            orchestrator.start()
            withTimeout(TIMEOUT_MILLIS) { registry.current.first { it != null } }
            mac.state.first { it is ConnectionState.Ready }
            val received = async(Dispatchers.IO) { mac.receive(Channel.CHANNEL_NOTIFY).first() }
            // Wait for the Mac-side subscription to exist before posting.
            delay(SUBSCRIBE_SETTLE_MILLIS)

            LiveNotificationEventSink.onNotificationPosted(notificationPosted { key = "loopback-key" })

            assertEquals("loopback-key", withTimeout(TIMEOUT_MILLIS) { received.await() }.notificationPosted.key)
        } finally {
            orchestrator.close()
            mac.close()
        }
    }

    private companion object {
        const val TIMEOUT_MILLIS = 10_000L
        const val SUBSCRIBE_SETTLE_MILLIS = 200L
    }
}
