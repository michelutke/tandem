package dev.tandem.feature.mirror

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.mirrorDeclined
import dev.tandem.protocol.v1.requestMediaTicket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch

/**
 * On-phone mirror start prompt (E61-16, SPEC.md "Mirror request", invariant 8). A `MirrorRequest`
 * only shows [presenter]'s prompt; capture starts solely through [onStartTapped], which runs
 * [onUserStart] (the seam for `MirrorConsent.grantFromUserAction`, E62-06) and the system
 * MediaProjection consent. Decline, dismiss, 30 s without a tap or denied consent send
 * `MirrorDeclined`; `RequestMediaTicket` is sent only after consent is granted.
 */
class MirrorPromptController(
    private val session: TandemSession,
    private val presenter: MirrorPromptPresenter,
    private val starter: MirrorSessionStarter,
    private val peerName: String,
    private val scope: CoroutineScope,
    private val onUserStart: () -> Unit,
) {
    private var promptPending = false
    private var timeoutJob: Job? = null

    fun start() {
        scope.launch {
            session
                .receive(Channel.CHANNEL_CONTROL)
                .filter { it.hasMirrorRequest() }
                .collect { onMirrorRequest() }
        }
    }

    private suspend fun onMirrorRequest() {
        if (promptPending) return
        if (starter.state != MirrorSessionState.NotStarted) {
            sendDeclined()
            return
        }
        promptPending = true
        presenter.show(peerName)
        timeoutJob =
            scope.launch {
                delay(PROMPT_TIMEOUT_MILLIS)
                onDeclineOrDismiss()
            }
    }

    fun onStartTapped() {
        if (!promptPending) return
        closePrompt()
        onUserStart()
        starter.onLocalStartAction()
    }

    fun onDeclineOrDismiss() {
        if (!promptPending) return
        closePrompt()
        scope.launch { sendDeclined() }
    }

    fun onConsentResult(granted: Boolean) {
        if (starter.state != MirrorSessionState.AwaitingConsent) return
        starter.onConsentResult(granted)
        scope.launch {
            if (granted) {
                session.send(Channel.CHANNEL_CONTROL) { requestMediaTicket = requestMediaTicket { } }
            } else {
                sendDeclined()
            }
        }
    }

    private fun closePrompt() {
        promptPending = false
        timeoutJob?.cancel()
        presenter.remove()
    }

    private suspend fun sendDeclined() {
        session.send(Channel.CHANNEL_CONTROL) { mirrorDeclined = mirrorDeclined { } }
    }

    private companion object {
        const val PROMPT_TIMEOUT_MILLIS = 30_000L
    }
}
