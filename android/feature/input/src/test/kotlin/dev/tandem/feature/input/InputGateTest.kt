package dev.tandem.feature.input

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.globalAction
import dev.tandem.protocol.v1.inputEvent
import dev.tandem.protocol.v1.setText
import dev.tandem.protocol.v1.tap
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** InputGate E62-06 tests (`docs/planning/backlog/phase-6.yaml` E62-06's `tdd:` list). Plain JUnit5. */
class InputGateTest {
    private val sessionId = ByteString.copyFromUtf8("session-1")
    private val boundSessionId = sessionId
    private val actions = FakeAccessibilityActions()
    private val consent = MirrorConsent()
    private var mediaActive = true
    private var peer: String? = "peer-a"
    private var indicatorShowing = true
    private val drops = mutableListOf<Pair<GateDropReason, String>>()
    private val gate =
        InputGate(
            consent = consent,
            live =
                object : LiveGateState {
                    override fun mediaActive() = mediaActive

                    override fun currentPeer() = peer

                    override fun indicatorShowing() = indicatorShowing
                },
            handler = InputActionHandler(actions, sdkInt = 34),
            translator = GestureTranslator(actions),
            dropLog = { reason, eventType -> drops += reason to eventType },
        )
    private val window = Size(540, 1200)
    private val display = Size(1080, 2400)

    private fun back(id: ByteString = sessionId) =
        inputEvent {
            this.sessionId = id
            globalAction = globalAction { action = GlobalActionKind.GLOBAL_ACTION_KIND_BACK }
        }

    private fun userStartsMirror() = consent.grantFromUserAction(sessionId, "peer-a")

    @Test
    fun inputGate_noActiveMirrorSession_droppedAndDispatcherNeverCalled() {
        assertEquals(InputResult.NoOp, gate.handle(back(), window, display))
        assertTrue(actions.globalActions.isEmpty())
        assertEquals(listOf(GateDropReason.NoConsent to "GLOBAL_ACTION"), drops)
    }

    @Test
    fun inputGate_droppedSetTextFrame_logEntryOmitsTextAndCoordinates() {
        val event =
            inputEvent {
                this.sessionId = boundSessionId
                setText = setText { text = "secret-text" }
            }
        gate.handle(event, window, display)
        assertEquals(listOf(GateDropReason.NoConsent to "SET_TEXT"), drops)
        assertFalse(drops.toString().contains("secret-text"))
    }

    @Test
    fun inputGate_sessionReferenceMismatch_frameDropped() {
        userStartsMirror()
        gate.handle(back(ByteString.copyFromUtf8("other")), window, display)
        assertTrue(actions.globalActions.isEmpty())
        assertEquals(GateDropReason.SessionMismatch, drops.single().first)
    }

    @Test
    fun inputGate_indicatorNotShowing_frameDropped() {
        userStartsMirror()
        indicatorShowing = false
        gate.handle(back(), window, display)
        assertTrue(actions.globalActions.isEmpty())
        assertEquals(GateDropReason.IndicatorHidden, drops.single().first)
    }

    @Test
    fun inputGate_activeBoundSession_forwardsEventToDispatcher() {
        userStartsMirror()
        assertEquals(InputResult.Performed, gate.handle(back(), window, display))
        assertEquals(1, actions.globalActions.size)
        val point =
            tap {
                x = 270
                y = 600
            }
        val tapEvent =
            inputEvent {
                this.sessionId = boundSessionId
                tap = point
            }
        assertEquals(InputResult.Performed, gate.handle(tapEvent, window, display))
        assertEquals(1, actions.strokes.size)
        assertTrue(drops.isEmpty())
    }

    @Test
    fun inputGate_consentButNoMediaConnection_frameDropped() {
        userStartsMirror()
        mediaActive = false
        gate.handle(back(), window, display)
        assertTrue(actions.globalActions.isEmpty())
        assertEquals(GateDropReason.MediaInactive, drops.single().first)
    }

    @Test
    fun inputGate_afterSessionEnd_droppedEvenIfMediaReturns() {
        userStartsMirror()
        gate.handle(back(), window, display)
        mediaActive = false
        gate.handle(back(), window, display)
        mediaActive = true
        gate.handle(back(), window, display)
        assertEquals(1, actions.globalActions.size)
        assertEquals(listOf(GateDropReason.MediaInactive, GateDropReason.NoConsent), drops.map { it.first })
    }

    @Test
    fun inputGate_mirrorStopped_closesGate() {
        userStartsMirror()
        consent.revoke()
        gate.handle(back(), window, display)
        assertTrue(actions.globalActions.isEmpty())
    }

    @Test
    fun inputGate_peerChange_closesGateAndStaysClosed() {
        userStartsMirror()
        peer = "peer-b"
        gate.handle(back(), window, display)
        peer = "peer-a"
        gate.handle(back(), window, display)
        assertTrue(actions.globalActions.isEmpty())
        assertEquals(listOf(GateDropReason.PeerChanged, GateDropReason.NoConsent), drops.map { it.first })
    }

    @Test
    fun inputGate_unknownPeer_failsClosed() {
        userStartsMirror()
        peer = null
        gate.handle(back(), window, display)
        assertTrue(actions.globalActions.isEmpty())
    }

    @Test
    fun inputGate_unsetEventCase_dropped() {
        userStartsMirror()
        assertEquals(InputResult.NoOp, gate.handle(inputEvent { this.sessionId = boundSessionId }, window, display))
    }

    @Test
    fun inputGate_indicatorDismissed_closesGateAndStaysClosed() {
        userStartsMirror()
        indicatorShowing = false
        gate.handle(back(), window, display)
        indicatorShowing = true
        gate.handle(back(), window, display)
        assertTrue(actions.globalActions.isEmpty())
    }
}
