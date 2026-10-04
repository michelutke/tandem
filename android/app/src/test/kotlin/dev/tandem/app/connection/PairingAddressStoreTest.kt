package dev.tandem.app.connection

import dev.tandem.core.transport.reconnect.CandidateAddress
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class PairingAddressStoreTest {
    @TempDir
    lateinit var dir: File

    @Test
    fun addresses_savedThenReopened_returnedInOrder() {
        PairingAddressStore(File(dir, "addresses")).save(listOf("192.168.1.5", "fe80::1"), 5555)

        val reopened = PairingAddressStore(File(dir, "addresses"))

        assertEquals(
            listOf(CandidateAddress("192.168.1.5", 5555), CandidateAddress("fe80::1", 5555)),
            reopened.addresses(),
        )
    }

    @Test
    fun addresses_noFile_empty() {
        assertEquals(emptyList<CandidateAddress>(), PairingAddressStore(File(dir, "missing")).addresses())
    }

    @Test
    fun addresses_cleared_empty() {
        val store = PairingAddressStore(File(dir, "addresses")).apply { save(listOf("10.0.0.2"), 1) }

        store.clear()

        assertEquals(emptyList<CandidateAddress>(), store.addresses())
    }
}
