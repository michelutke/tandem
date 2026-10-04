package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.globalAction
import dev.tandem.protocol.v1.inputEvent
import dev.tandem.protocol.v1.setText
import dev.tandem.protocol.v1.tap
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

/** E62-08: the gate-with-recording-dispatcher behind `INPUTWATCH`/`INPUTSTATS`. */
class RemoteInputHarnessTest {
    private val sessionId = ByteString.copyFrom(ByteArray(16) { it.toByte() })
    private val harness = RemoteInputHarness()

    @Test
    fun remoteInputHarness_tapWithoutMirrorSession_zeroDispatcherCallsOneDropRecord() {
        harness.handle(
            inputEvent {
                this.sessionId = this@RemoteInputHarnessTest.sessionId
                tap = tap { x = 10 }
            },
        )

        assertEquals(
            "OK INPUT DISPATCHER_CALLS=0 DROPS=1 RATE_LIMITED=0 LAST_DROP=NoConsent:TAP",
            harness.statsLine(),
        )
    }

    @Test
    fun remoteInputHarness_everyEventKindWithoutMirrorSession_neverReachesDispatcher() {
        harness.handle(
            inputEvent {
                this.sessionId = this@RemoteInputHarnessTest.sessionId
                globalAction = globalAction { action = GlobalActionKind.GLOBAL_ACTION_KIND_HOME }
            },
        )
        harness.handle(
            inputEvent {
                this.sessionId = this@RemoteInputHarnessTest.sessionId
                setText = setText { text = "TANDEM-CANARY-x" }
            },
        )

        assertEquals(
            "OK INPUT DISPATCHER_CALLS=0 DROPS=2 RATE_LIMITED=0 LAST_DROP=NoConsent:SET_TEXT",
            harness.statsLine(),
        )
    }

    @Test
    fun remoteInputHarness_statsLineAfterSetTextCanary_omitsCanary() {
        harness.handle(
            inputEvent {
                this.sessionId = this@RemoteInputHarnessTest.sessionId
                setText = setText { text = "TANDEM-CANARY-x" }
            },
        )

        assertFalse(harness.statsLine().contains("CANARY"))
    }

    @Test
    fun remoteInputHarness_noEvents_reportsNoDrops() {
        assertEquals(
            "OK INPUT DISPATCHER_CALLS=0 DROPS=0 RATE_LIMITED=0 LAST_DROP=NONE",
            harness.statsLine(),
        )
    }
}
