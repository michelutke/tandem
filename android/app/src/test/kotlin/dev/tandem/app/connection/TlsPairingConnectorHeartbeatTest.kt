package dev.tandem.app.connection

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.core.testing.ManualElapsedRealtime
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.HeartbeatDependencies
import dev.tandem.core.transport.heartbeat.DeviceIdleSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.heartbeat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Test
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.time.Clock
import javax.net.ssl.X509KeyManager
import kotlin.time.Duration.Companion.seconds

/**
 * The pairing-candidate session must answer the Mac's `Heartbeat` (SPEC.md Heartbeat, D-69): the
 * Mac cancels a candidate connection that stays silent for 45 s, long before the 120 s the owner
 * has to click Pair. Real sessions over `InMemoryDuplexPipe`, so real threads.
 */
class TlsPairingConnectorHeartbeatTest {
    @Test
    fun tlsPairingConnector_macHeartbeatDuringConfirmation_phoneRepliesWithinOneSecond() =
        runBlocking(Dispatchers.IO) {
            val pipe = InMemoryDuplexPipe()
            val macSession = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)
            val keyHandle = SoftwareIdentityKeyStore(Clock.systemUTC()).getOrCreate("phone", preferStrongBox = false)
            val connector =
                TlsPairingConnector(
                    keyManager = FixedKeyManager(keyHandle.certificate, keyHandle.privateKey),
                    clock = Clock.systemUTC(),
                    ioDispatcher = Dispatchers.IO,
                    sessionDispatcher = Dispatchers.IO,
                    identity = IdentityBootstrap({}, Dispatchers.IO),
                    dialer = { _, _, _ -> pipe.endpointA to ByteArray(0) },
                    heartbeatDependencies = HeartbeatDependencies(ManualElapsedRealtime(), ActiveDeviceIdleSource()),
                )
            val phoneSession = connector.connect("10.0.0.2", PORT, PinSource { emptyList() }).session
            macSession.state.first { it is ConnectionState.Ready }

            val reply = CompletableDeferred<Unit>()
            val collector =
                launch(start = CoroutineStart.UNDISPATCHED) {
                    macSession
                        .receive(
                            Channel.CHANNEL_CONTROL,
                        ).first { it.payloadCase == Envelope.PayloadCase.HEARTBEAT }
                    reply.complete(Unit)
                }
            macSession.send(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} }

            withTimeout(1.seconds) { reply.await() }
            collector.cancel()
            phoneSession.close()
            macSession.close()
        }

    private class ActiveDeviceIdleSource : DeviceIdleSource {
        override val isIdle: StateFlow<Boolean> = MutableStateFlow(false)
        override val screenOn: Flow<Unit> = emptyFlow()
    }

    private class FixedKeyManager(
        private val certificate: X509Certificate,
        private val privateKey: PrivateKey,
    ) : X509KeyManager {
        override fun getClientAliases(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
        ): Array<String> = arrayOf(ALIAS)

        override fun chooseClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out java.security.Principal>?,
            socket: java.net.Socket?,
        ): String = ALIAS

        override fun getServerAliases(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
        ): Array<String>? = null

        override fun chooseServerAlias(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
            socket: java.net.Socket?,
        ): String? = null

        override fun getCertificateChain(alias: String?): Array<X509Certificate> = arrayOf(certificate)

        override fun getPrivateKey(alias: String?): PrivateKey = privateKey
    }

    private companion object {
        const val ALIAS = "phone"
        const val PORT = 8443
    }
}
