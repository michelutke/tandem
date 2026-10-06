package dev.tandem.app.egress

import android.os.ParcelFileDescriptor
import android.os.Process
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.app.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// instrumented (E71-14): samples the kernel socket tables for the app UID while the app runs.
// `/proc/net/*` is not readable from an app process on API 29+, so the dump is taken through the
// shell identity of UiAutomation. `macAddress`/`tandemPort` instrumentation arguments name the only
// allowed remote endpoint (emulator host loopback: 10.0.2.2); without them no socket may exist.
@RunWith(AndroidJUnit4::class)
class EgressAuditInstrumentedTest {
    @Test
    fun androidEgressAudit_parseProcNetFixture_decodesRemoteEndpointAndUid() {
        val dump =
            """
            sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
             0: 0F02000A:C350 0202000A:1B3A 01 00000000:00000000 00:00000000 00000000 10123 0 1 1 0 0
            """.trimIndent()

        val sockets = ProcNetSockets.parse(dump)

        assertEquals(listOf(ProcNetSocket(10123, "10.0.2.2", 0x1B3A)), sockets)
    }

    @Test
    fun androidEgressAudit_fullSessionOnEmulator_onlyMacEndpointsForAppUid() {
        val arguments = InstrumentationRegistry.getArguments()
        val allowed =
            arguments.getString("macAddress")?.let { address ->
                address to checkNotNull(arguments.getString("tandemPort")).toInt()
            }

        ActivityScenario.launch(MainActivity::class.java).use {
            val appSockets = ProcNetSockets.parse(readSocketTables()).filter { it.uid == Process.myUid() }

            val violations = appSockets.filter { (it.remoteAddress to it.remotePort) != allowed }
            assertTrue("sockets owned by the app UID with other remote endpoints: $violations", violations.isEmpty())
        }
    }

    private fun readSocketTables(): String {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val descriptor = automation.executeShellCommand("cat /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6")
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
    }
}
