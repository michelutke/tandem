package dev.tandem.core.protocol.handshake

import dev.tandem.core.protocol.multiplex.ChannelMultiplexer
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.VersionHello
import dev.tandem.protocol.v1.versionHello
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Clock
import kotlin.time.Duration.Companion.seconds

/**
 * `VersionHello` exchange over CONTROL (E12-15; SPEC.md #versioning-and-capability-negotiation,
 * D-63; aligned with the macOS twin, E12-07's `VersionHandshake`). [perform] sends this side's own
 * hello as the first CONTROL frame through [multiplexer] without waiting for the peer's (SPEC.md
 * "Exchange rule"), then waits up to [HELLO_DEADLINE]
 * (SPEC.md #timeouts-connection-limits-and-resource-caps, E01-22) for the peer's — on the injected
 * [dispatcher], so the deadline is exercised in virtual time in tests (`TestClock` + `runTest`,
 * E00-18) rather than a real 5 s wait. A peer `major` differing from [PROTOCOL_MAJOR] is
 * [HandshakeFailure.VersionMismatch] regardless of `minor`; no peer hello inside [HELLO_DEADLINE]
 * is [HandshakeFailure.Timeout]. Neither outcome tears down [multiplexer]'s connection itself:
 * that remains owned by whichever later issue wires a real socket to this seam (E12-08), per
 * [ChannelMultiplexer]'s own close-ownership note.
 *
 * [awaitReady] is the gate a feature-channel sender MUST suspend on before calling
 * [ChannelMultiplexer.send] on any channel but CONTROL (SPEC.md: "No application frame... MAY be
 * sent... before both hellos have been exchanged"): it completes only once [perform] reaches
 * [HandshakeOutcome.Ready], and completes exceptionally with [HandshakeFailedException] if
 * [perform] instead reaches [HandshakeOutcome.Failed].
 */
class VersionHandshake(
    private val multiplexer: ChannelMultiplexer,
    private val clock: Clock,
    private val dispatcher: CoroutineDispatcher,
) {
    private val ready = CompletableDeferred<NegotiatedSession>()

    suspend fun awaitReady(): NegotiatedSession = ready.await()

    suspend fun perform(): HandshakeOutcome =
        withContext(dispatcher) {
            sendOwnHello()
            val outcome = outcomeFor(withTimeoutOrNull(HELLO_DEADLINE) { awaitPeerHello() })
            complete(outcome)
            outcome
        }

    private suspend fun sendOwnHello() {
        multiplexer.send(Channel.CHANNEL_CONTROL) {
            versionHello =
                versionHello {
                    major = PROTOCOL_MAJOR
                    minor = PROTOCOL_MINOR
                    capabilities = 0
                }
        }
    }

    private suspend fun awaitPeerHello(): VersionHello =
        multiplexer
            .inbound(Channel.CHANNEL_CONTROL)
            .first { it.payload.payloadCase == Envelope.PayloadCase.VERSION_HELLO }
            .payload.versionHello

    private fun outcomeFor(peerHello: VersionHello?): HandshakeOutcome =
        when {
            peerHello == null -> {
                HandshakeOutcome.Failed(HandshakeFailure.Timeout)
            }

            peerHello.major != PROTOCOL_MAJOR -> {
                HandshakeOutcome.Failed(HandshakeFailure.VersionMismatch(peerHello.major, peerHello.minor))
            }

            else -> {
                HandshakeOutcome.Ready(NegotiatedSession(peerHello.minor, peerHello.capabilities, clock.instant()))
            }
        }

    private fun complete(outcome: HandshakeOutcome) {
        when (outcome) {
            is HandshakeOutcome.Ready -> ready.complete(outcome.session)
            is HandshakeOutcome.Failed -> ready.completeExceptionally(HandshakeFailedException(outcome.reason))
        }
    }

    companion object {
        const val PROTOCOL_MAJOR = 1
        const val PROTOCOL_MINOR = 0
        val HELLO_DEADLINE = 5.seconds
    }
}
