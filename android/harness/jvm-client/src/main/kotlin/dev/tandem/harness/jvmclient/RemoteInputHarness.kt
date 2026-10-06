package dev.tandem.harness.jvmclient

import dev.tandem.feature.input.AccessibilityActions
import dev.tandem.feature.input.DropLog
import dev.tandem.feature.input.FocusedInput
import dev.tandem.feature.input.GateDropReason
import dev.tandem.feature.input.GestureStroke
import dev.tandem.feature.input.GestureTranslator
import dev.tandem.feature.input.InputActionHandler
import dev.tandem.feature.input.InputGate
import dev.tandem.feature.input.LiveGateState
import dev.tandem.feature.input.MirrorConsent
import dev.tandem.feature.input.Size
import dev.tandem.protocol.v1.InputEvent
import java.time.Clock
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/** One `input_dropped` entry: reason and event type name only, exactly what the gate's [DropLog] receives. */
internal data class InputDropRecord(
    val reason: GateDropReason,
    val eventType: String,
)

/**
 * The phone-side `InputEvent` path for the `INPUTWATCH`/`INPUTSTATS` commands (E62-08 integration
 * variant): the real [InputGate] over a real [InputActionHandler]/[GestureTranslator], with a
 * recording [AccessibilityActions] as the dispatcher. No [MirrorConsent] is ever granted here, so a
 * real Mac that sends input with no mirror session must produce zero dispatcher calls and exactly
 * one [InputDropRecord] per event. The recording keeps counts only, never coordinates or text.
 */
internal class RemoteInputHarness(
    clock: Clock = Clock.systemUTC(),
) {
    private val dispatcherCalls = AtomicInteger()
    private val drops = CopyOnWriteArrayList<InputDropRecord>()
    private val rateLimited = AtomicInteger()

    private val actions =
        object : AccessibilityActions {
            override fun performGlobalAction(action: Int): Boolean = record()

            override fun findFocusedInput(): FocusedInput? {
                record()
                return null
            }

            override fun dispatchGesture(stroke: GestureStroke): Boolean = record()

            private fun record(): Boolean {
                dispatcherCalls.incrementAndGet()
                return true
            }
        }

    private val noLiveState =
        object : LiveGateState {
            override fun mediaActive(): Boolean = false

            override fun currentPeer(): String? = null

            override fun indicatorShowing(): Boolean = false
        }

    private val dropLog =
        object : DropLog {
            override fun dropped(
                reason: GateDropReason,
                eventType: String,
            ) {
                drops += InputDropRecord(reason, eventType)
            }

            override fun rateLimited(count: Int) {
                rateLimited.addAndGet(count)
            }
        }

    private val gate =
        InputGate(
            consent = MirrorConsent(),
            live = noLiveState,
            handler = InputActionHandler(actions),
            translator = GestureTranslator(actions),
            dropLog = dropLog,
            clock = clock,
        )

    fun handle(event: InputEvent) {
        gate.handle(event, WINDOW, DISPLAY)
    }

    /** `OK INPUT DISPATCHER_CALLS=<n> DROPS=<n> RATE_LIMITED=<n> LAST_DROP=<REASON:EVENT|NONE>`. */
    fun statsLine(): String {
        val last = drops.lastOrNull()?.let { "${it.reason.name}:${it.eventType}" } ?: "NONE"
        return "OK INPUT DISPATCHER_CALLS=${dispatcherCalls.get()} DROPS=${drops.size} " +
            "RATE_LIMITED=${rateLimited.get()} LAST_DROP=$last"
    }

    private companion object {
        val WINDOW = Size(540, 1200)
        val DISPLAY = Size(1080, 2400)
    }
}
