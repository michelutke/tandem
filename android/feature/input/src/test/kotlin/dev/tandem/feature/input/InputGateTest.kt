package dev.tandem.feature.input

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.TextEdit
import dev.tandem.protocol.v1.globalAction
import dev.tandem.protocol.v1.inputEvent
import dev.tandem.protocol.v1.setText
import dev.tandem.protocol.v1.swipe
import dev.tandem.protocol.v1.tap
import dev.tandem.protocol.v1.textEdit
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneId

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
    private val rateLogs = mutableListOf<Int>()
    private var nowMillis = 0L
    private val clock =
        object : Clock() {
            override fun getZone(): ZoneId = ZoneId.of("UTC")

            override fun withZone(zone: ZoneId): Clock = this

            override fun instant(): Instant = Instant.ofEpochMilli(nowMillis)
        }
    private val gate =
        InputGate(
            consent = consent,
            live =
                object : LiveGateState {
                    override fun mediaActive() = mediaActive

                    override fun currentPeer() = peer

                    override fun indicatorShowing() = indicatorShowing
                },
            handler = InputActionHandler(actions),
            translator = GestureTranslator(actions),
            dropLog =
                object : DropLog {
                    override fun dropped(
                        reason: GateDropReason,
                        eventType: String,
                    ) {
                        drops += reason to eventType
                    }

                    override fun rateLimited(count: Int) {
                        rateLogs += count
                    }
                },
            clock = clock,
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
    fun inputGate_indicatorDismissedAfterShown_closesGateAndStaysClosed() {
        userStartsMirror()
        gate.handle(back(), window, display)
        indicatorShowing = false
        gate.handle(back(), window, display)
        indicatorShowing = true
        gate.handle(back(), window, display)
        assertEquals(1, actions.globalActions.size)
    }

    @Test
    fun inputGate_indicatorNotYetShown_droppedWithoutRevokingThenOpens() {
        userStartsMirror()
        indicatorShowing = false
        gate.handle(back(), window, display)
        assertTrue(consent.grant != null)
        indicatorShowing = true
        assertEquals(InputResult.Performed, gate.handle(back(), window, display))
        assertEquals(listOf(GateDropReason.IndicatorHidden), drops.map { it.first })
    }

    @Test
    fun inputGate_staleSession_droppedWithoutRevokingConsent() {
        userStartsMirror()
        gate.handle(back(ByteString.copyFromUtf8("stale")), window, display)
        assertEquals(InputResult.Performed, gate.handle(back(), window, display))
        assertEquals(listOf(GateDropReason.SessionMismatch), drops.map { it.first })
    }

    private fun textEditEvent(edit: TextEdit) =
        inputEvent {
            this.sessionId = boundSessionId
            textEdit = edit
        }

    @Test
    fun inputGate_deleteBackwardOutsideRange_dropped() {
        userStartsMirror()
        val input = FakeFocusedInput("hello")
        actions.focusedInput = input
        listOf(0, 65, Int.MAX_VALUE, -1).forEach { count ->
            gate.handle(textEditEvent(textEdit { deleteBackward = count }), window, display)
        }
        assertEquals(4, drops.count { it.first == GateDropReason.OutOfRange })
        assertEquals("hello", input.text)
    }

    @Test
    fun inputGate_insertOver4096CodePoints_dropped() {
        userStartsMirror()
        val tooLong = "\uD83D\uDE00".repeat(4097)
        val atLimit = "\uD83D\uDE00".repeat(4096)
        gate.handle(textEditEvent(textEdit { insert = tooLong }), window, display)
        assertEquals(listOf(GateDropReason.OutOfRange to "TEXT_EDIT"), drops)
        gate.handle(textEditEvent(textEdit { insert = atLimit }), window, display)
        assertEquals(1, drops.size)
    }

    @Test
    fun inputGate_setTextAtLimitInEmoji_notDropped() {
        userStartsMirror()
        val event =
            inputEvent {
                this.sessionId = boundSessionId
                setText = setText { text = "\uD83D\uDE00".repeat(4096) }
            }
        gate.handle(event, window, display)
        assertTrue(drops.isEmpty())
    }

    @Test
    fun inputGate_floodOfOutOfRangeEvents_logLinesBoundedByBucket() {
        userStartsMirror()
        repeat(1000) { gate.handle(textEditEvent(textEdit { deleteBackward = 0 }), window, display) }
        assertEquals(240, drops.size)
    }

    @Test
    fun inputGate_burstOf1000Events_atMost240Dispatched() {
        userStartsMirror()
        repeat(1000) { gate.handle(back(), window, display) }
        assertEquals(240, actions.globalActions.size)
        nowMillis = 1000
        gate.handle(back(), window, display)
        assertEquals(listOf(760), rateLogs)
        assertTrue(drops.isEmpty())
    }

    @Test
    fun inputGate_rateAfterBurst_refillsAt120PerSecond() {
        userStartsMirror()
        repeat(240) { gate.handle(back(), window, display) }
        nowMillis = 500
        repeat(100) { gate.handle(back(), window, display) }
        assertEquals(300, actions.globalActions.size)
    }

    @Test
    fun inputGate_setTextOver4096Chars_dropped() {
        userStartsMirror()
        val tooLong =
            inputEvent {
                this.sessionId = boundSessionId
                setText = setText { text = "a".repeat(4097) }
            }
        val atLimit =
            inputEvent {
                this.sessionId = boundSessionId
                setText = setText { text = "a".repeat(4096) }
            }
        gate.handle(tooLong, window, display)
        assertEquals(listOf(GateDropReason.OutOfRange to "SET_TEXT"), drops)
        assertFalse(drops.toString().contains("aaaa"))
        assertEquals(InputResult.NoOp, gate.handle(atLimit, window, display))
    }

    @Test
    fun inputGate_swipeDurationOutsideRange_droppedAndGateStaysOpen() {
        userStartsMirror()
        listOf(0, 5001).forEach { duration ->
            val move =
                swipe {
                    x1 = 10
                    y1 = 10
                    x2 = 20
                    y2 = 20
                    durationMs = duration
                }
            val event =
                inputEvent {
                    this.sessionId = boundSessionId
                    swipe = move
                }
            gate.handle(event, window, display)
        }
        assertEquals(2, drops.count { it.first == GateDropReason.OutOfRange })
        assertEquals(InputResult.Performed, gate.handle(back(), window, display))
    }

    @Test
    fun inputGate_indicatorOverlayDetached_frameDropped() {
        val overlay = FakeOverlayBadge()
        val indicator = RemoteInputIndicator(FakeNotificationPresenter(), overlay)
        indicator.show()
        val overlayGate = gateWith(IndicatorGateState(indicator, { true }, { "peer-a" }))
        userStartsMirror()
        overlay.attached = false
        overlayGate.handle(back(), window, display)
        assertTrue(actions.globalActions.isEmpty())
        assertEquals(GateDropReason.IndicatorHidden, drops.single().first)
    }

    @Test
    fun inputGate_notificationDismissed_frameDropped() {
        val notification = FakeNotificationPresenter()
        val indicator = RemoteInputIndicator(notification, FakeOverlayBadge())
        indicator.show()
        val indicatorGate = gateWith(IndicatorGateState(indicator, { true }, { "peer-a" }))
        userStartsMirror()
        assertEquals(InputResult.Performed, indicatorGate.handle(back(), window, display))
        notification.posted = false
        indicatorGate.handle(back(), window, display)
        assertEquals(1, actions.globalActions.size)
    }

    private fun gateWith(live: LiveGateState) =
        InputGate(
            consent = consent,
            live = live,
            handler = InputActionHandler(actions),
            translator = GestureTranslator(actions),
            dropLog =
                object : DropLog {
                    override fun dropped(
                        reason: GateDropReason,
                        eventType: String,
                    ) {
                        drops += reason to eventType
                    }

                    override fun rateLimited(count: Int) = Unit
                },
            clock = clock,
        )
}
