package dev.tandem.app.shell

import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.core.transport.reconnect.CandidateAddress
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

// E20-25 tdd: unit: scanAccepted_validInvite_savesAddressesAndHandsInviteToPairingFlow
class ScanAcceptedTest {
    @TempDir
    lateinit var dir: File

    @Test
    fun scanAccepted_validInvite_savesAddressesAndHandsInviteToPairingFlow() {
        val store = PairingAddressStore(File(dir, "pairing-addresses"))
        val started = mutableListOf<PairingInvite>()
        val invite = PairingInvite(ByteArray(32), ByteArray(16), listOf("192.168.1.5", "10.0.0.2"), 7443, "MacBook Pro")

        onScanAccepted(invite, store, PairingStarter { started += it })

        assertEquals(listOf(invite), started)
        assertEquals(
            listOf(CandidateAddress("192.168.1.5", 7443), CandidateAddress("10.0.0.2", 7443)),
            store.addresses(),
        )
    }
}
