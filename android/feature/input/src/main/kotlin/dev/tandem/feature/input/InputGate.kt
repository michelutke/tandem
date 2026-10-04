package dev.tandem.feature.input

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.InputEvent

enum class GateDropReason { NoConsent, SessionMismatch, MediaInactive, PeerChanged, IndicatorHidden, UnknownEvent }

fun interface DropLog {
    /** Reason and event type name only; never coordinates or text. */
    fun dropped(
        reason: GateDropReason,
        eventType: String,
    )
}

/** Live conditions the gate re-reads on every event; null peer or any false value fails closed. */
interface LiveGateState {
    fun mediaActive(): Boolean

    fun currentPeer(): String?

    fun indicatorShowing(): Boolean
}

/**
 * Records the user's explicit decision to start a mirror session on the phone, bound to one control
 * session id and one peer fingerprint. [grantFromUserAction] is the only way to open it.
 */
class MirrorConsent {
    class Grant(
        val sessionId: ByteString,
        val peerFingerprint: String,
    )

    @Volatile
    var grant: Grant? = null
        private set

    fun grantFromUserAction(
        sessionId: ByteString,
        peerFingerprint: String,
    ) {
        grant = Grant(sessionId, peerFingerprint)
    }

    fun revoke() {
        grant = null
    }
}

/**
 * Invariant 8 gate in front of [InputActionHandler] and [GestureTranslator]. Input executes only
 * while the user-started consent, the media connection, the same peer and the on-phone indicator
 * all hold; the first failed check revokes consent so the gate never reopens on its own, and
 * nothing is queued or replayed. Unknown state fails closed. Never logs event content.
 */
class InputGate(
    private val consent: MirrorConsent,
    private val live: LiveGateState,
    private val handler: InputActionHandler,
    private val translator: GestureTranslator,
    private val dropLog: DropLog,
) {
    fun handle(
        event: InputEvent,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta = RotationDelta.None,
    ): InputResult {
        val reason = denial(event)
        if (reason != null) {
            if (reason != GateDropReason.NoConsent) consent.revoke()
            return drop(reason, event)
        }
        return when (event.eventCase) {
            InputEvent.EventCase.TAP -> translator.handle(event.tap, window, display, rotationDelta)
            InputEvent.EventCase.SWIPE -> translator.handle(event.swipe, window, display, rotationDelta)
            InputEvent.EventCase.SCROLL -> translator.handle(event.scroll, window, display, rotationDelta)
            InputEvent.EventCase.GLOBAL_ACTION -> handler.handle(event.globalAction)
            InputEvent.EventCase.SET_TEXT -> handler.handle(event.setText)
            InputEvent.EventCase.TEXT_EDIT -> handler.handle(event.textEdit)
            else -> drop(GateDropReason.UnknownEvent, event)
        }
    }

    private fun drop(
        reason: GateDropReason,
        event: InputEvent,
    ): InputResult {
        dropLog.dropped(reason, event.eventCase.name)
        return InputResult.NoOp
    }

    private fun denial(event: InputEvent): GateDropReason? {
        val grant = consent.grant ?: return GateDropReason.NoConsent
        return when {
            event.sessionId != grant.sessionId -> GateDropReason.SessionMismatch
            live.currentPeer() != grant.peerFingerprint -> GateDropReason.PeerChanged
            !live.mediaActive() -> GateDropReason.MediaInactive
            !live.indicatorShowing() -> GateDropReason.IndicatorHidden
            else -> null
        }
    }
}
