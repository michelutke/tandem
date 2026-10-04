package dev.tandem.feature.input

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.InputEvent
import dev.tandem.protocol.v1.TextEdit
import java.time.Clock

enum class GateDropReason {
    NoConsent,
    SessionMismatch,
    MediaInactive,
    PeerChanged,
    IndicatorHidden,
    UnknownEvent,
    OutOfRange,
}

interface DropLog {
    /** Reason and event type name only; never coordinates or text. */
    fun dropped(
        reason: GateDropReason,
        eventType: String,
    )

    /** At most one call per second: how many events the token bucket dropped since the last call. */
    fun rateLimited(count: Int)
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
 * nothing is queued or replayed. A session mismatch, and an indicator that has not yet been seen
 * showing for the current grant, are dropped without revoking. Calls are serialized. Unknown state
 * fails closed. Never logs event content.
 */
class InputGate(
    private val consent: MirrorConsent,
    private val live: LiveGateState,
    private val handler: InputActionHandler,
    private val translator: GestureTranslator,
    private val dropLog: DropLog,
    clock: Clock,
) {
    private val bucket = TokenBucket(clock, RATE_PER_SECOND, BURST)
    private var rateDropped = 0
    private var lastRateLogMillis = clock.millis()
    private val clock = clock

    private var indicatorShownFor: MirrorConsent.Grant? = null

    @Synchronized
    fun handle(
        event: InputEvent,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta = RotationDelta.None,
    ): InputResult {
        flushRateLog()
        val reason = denial(event)
        return when {
            reason != null -> {
                drop(reason, event)
            }

            !bucket.tryAcquire() -> {
                rateLimitedDrop()
            }

            isOutOfRange(event) -> {
                drop(GateDropReason.OutOfRange, event)
            }

            else -> {
                dispatch(event, window, display, rotationDelta)
            }
        }
    }

    private fun dispatch(
        event: InputEvent,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta,
    ): InputResult =
        when (event.eventCase) {
            InputEvent.EventCase.TAP -> translator.handle(event.tap, window, display, rotationDelta)
            InputEvent.EventCase.SWIPE -> translator.handle(event.swipe, window, display, rotationDelta)
            InputEvent.EventCase.SCROLL -> translator.handle(event.scroll, window, display, rotationDelta)
            InputEvent.EventCase.GLOBAL_ACTION -> handler.handle(event.globalAction)
            InputEvent.EventCase.SET_TEXT -> handler.handle(event.setText)
            InputEvent.EventCase.TEXT_EDIT -> handler.handle(event.textEdit)
            else -> drop(GateDropReason.UnknownEvent, event)
        }

    private fun drop(
        reason: GateDropReason,
        event: InputEvent,
    ): InputResult {
        dropLog.dropped(reason, event.eventCase.name)
        return InputResult.NoOp
    }

    private fun rateLimitedDrop(): InputResult {
        rateDropped++
        flushRateLog()
        return InputResult.NoOp
    }

    private fun flushRateLog() {
        val now = clock.millis()
        if (rateDropped == 0 || now - lastRateLogMillis < RATE_LOG_INTERVAL_MS) return
        dropLog.rateLimited(rateDropped)
        rateDropped = 0
        lastRateLogMillis = now
    }

    private fun isOutOfRange(event: InputEvent): Boolean =
        when (event.eventCase) {
            InputEvent.EventCase.SET_TEXT -> exceedsTextLimit(event.setText.text)
            InputEvent.EventCase.SWIPE -> event.swipe.durationMs !in SWIPE_DURATION_RANGE_MS
            InputEvent.EventCase.TEXT_EDIT -> isTextEditOutOfRange(event.textEdit)
            else -> false
        }

    /** Stale or foreign sessions are only dropped; every other failed check revokes consent. */
    private fun denial(event: InputEvent): GateDropReason? {
        val grant = consent.grant ?: return GateDropReason.NoConsent
        val reason =
            if (event.sessionId != grant.sessionId) GateDropReason.SessionMismatch else liveDenial(grant)
        if (reason != null && !isDropOnly(reason, grant)) consent.revoke()
        return reason
    }

    private fun liveDenial(grant: MirrorConsent.Grant): GateDropReason? {
        val reason =
            when {
                live.currentPeer() != grant.peerFingerprint -> GateDropReason.PeerChanged
                !live.mediaActive() -> GateDropReason.MediaInactive
                !live.indicatorShowing() -> GateDropReason.IndicatorHidden
                else -> null
            }
        if (reason == null) indicatorShownFor = grant
        return reason
    }

    private fun isDropOnly(
        reason: GateDropReason,
        grant: MirrorConsent.Grant,
    ): Boolean =
        reason == GateDropReason.SessionMismatch ||
            (reason == GateDropReason.IndicatorHidden && indicatorShownFor !== grant)

    private companion object {
        const val RATE_PER_SECOND = 120
        const val BURST = 240
        const val RATE_LOG_INTERVAL_MS = 1000L
        val SWIPE_DURATION_RANGE_MS = 1..5000
    }
}

private const val MAX_TEXT_CODE_POINTS = 4096
private const val MAX_DELETE_BACKWARD = 64
private val DELETE_BACKWARD_RANGE = 1..MAX_DELETE_BACKWARD

private fun exceedsTextLimit(text: String): Boolean = text.codePointCount(0, text.length) > MAX_TEXT_CODE_POINTS

private fun isTextEditOutOfRange(edit: TextEdit): Boolean =
    when (edit.editCase) {
        TextEdit.EditCase.INSERT -> exceedsTextLimit(edit.insert)
        TextEdit.EditCase.DELETE_BACKWARD -> edit.deleteBackward !in DELETE_BACKWARD_RANGE
        else -> false
    }

/** Refills [ratePerSecond] tokens per second up to [burst]; each acquired token admits one event. */
class TokenBucket(
    private val clock: Clock,
    private val ratePerSecond: Int,
    private val burst: Int,
) {
    private var tokens = burst.toDouble()
    private var lastMillis = clock.millis()

    fun tryAcquire(): Boolean {
        val now = clock.millis()
        val refill = (now - lastMillis).coerceAtLeast(0) * ratePerSecond / MILLIS_PER_SECOND
        tokens = minOf(burst.toDouble(), tokens + refill)
        lastMillis = now
        if (tokens < 1.0) return false
        tokens -= 1.0
        return true
    }

    private companion object {
        const val MILLIS_PER_SECOND = 1000.0
    }
}
