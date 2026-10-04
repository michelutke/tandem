package dev.tandem.feature.mirror

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.mirrorDeclined
import dev.tandem.protocol.v1.requestMediaTicket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * On-phone mirror start prompt (E61-16, SPEC.md "Mirror request", invariant 8). A `MirrorRequest`
 * only shows [presenter]'s prompt; capture starts solely through [onStartTapped], which runs
 * [onUserStart] (the seam for `MirrorConsent.grantFromUserAction`, E62-06) and the system
 * MediaProjection consent. Decline, dismiss, 30 s without a tap or denied consent send
 * `MirrorDeclined`; `RequestMediaTicket` is sent only after consent is granted. [stop] (also run
 * when the control session ends) closes the prompt and makes every later tap, timeout or consent
 * result a no-op. The prompt is claimed atomically, so exactly one of decline and start happens.
 */
class MirrorPromptController(
    private val session: TandemSession,
    private val presenter: MirrorPromptPresenter,
    private val starter: MirrorSessionStarter,
    private val peerName: String,
    scope: CoroutineScope,
    private val onUserStart: () -> Unit,
) {
    private val job = SupervisorJob(scope.coroutineContext[Job])
    private val scope = scope + job
    private val promptPending = AtomicBoolean(false)
    private val stopped = AtomicBoolean(false)

    @Volatile
    private var timeoutJob: Job? = null

    fun start() {
        this.scope.launch {
            session.state.first { it is ConnectionState.Disconnected || it is ConnectionState.Failed }
            stop()
        }
        this.scope.launch {
            session
                .receive(Channel.CHANNEL_CONTROL)
                .filter { it.hasMirrorRequest() }
                .collect { onMirrorRequest() }
        }
    }

    private suspend fun onMirrorRequest() {
        if (stopped.get() || promptPending.get()) return
        if (starter.state != MirrorSessionState.NotStarted) {
            sendDeclined()
            return
        }
        promptPending.set(true)
        presenter.show(peerName)
        timeoutJob =
            scope.launch {
                delay(PROMPT_TIMEOUT_MILLIS)
                onDeclineOrDismiss()
            }
    }

    fun onStartTapped() {
        if (!closePrompt()) return
        onUserStart()
        starter.onLocalStartAction()
    }

    fun onDeclineOrDismiss() {
        if (!closePrompt()) return
        scope.launch { sendDeclined() }
    }

    fun onConsentResult(granted: Boolean) {
        if (stopped.get() || starter.state != MirrorSessionState.AwaitingConsent) return
        starter.onConsentResult(granted)
        scope.launch {
            if (granted) {
                send { requestMediaTicket = requestMediaTicket { } }
            } else {
                sendDeclined()
            }
        }
    }

    fun stop() {
        if (!stopped.compareAndSet(false, true)) return
        closePrompt()
        job.cancel()
    }

    private fun closePrompt(): Boolean {
        if (!promptPending.compareAndSet(true, false)) return false
        timeoutJob?.cancel()
        presenter.remove()
        return true
    }

    private suspend fun sendDeclined() {
        send { mirrorDeclined = mirrorDeclined { } }
    }

    private suspend fun send(payload: EnvelopeKt.Dsl.() -> Unit) {
        try {
            session.send(Channel.CHANNEL_CONTROL, payload)
        } catch (_: MultiplexerClosedException) {
            stop()
        } catch (_: IOException) {
            stop()
        }
    }

    private companion object {
        const val PROMPT_TIMEOUT_MILLIS = 30_000L
    }
}
