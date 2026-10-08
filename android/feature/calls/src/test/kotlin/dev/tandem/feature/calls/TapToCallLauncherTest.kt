package dev.tandem.feature.calls

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class TapToCallLauncherTest {
    private val started = mutableListOf<String>()
    private var failures = 0

    @Test
    fun tapToCallLauncher_accountLookupThrowsSecurityException_reportsFailureWithoutCalling() {
        val launcher =
            TapToCallLauncher(
                accountFor = { throw SecurityException("READ_PHONE_STATE revoked") },
                start = { address, _ -> started += address },
                onFailure = { failures++ },
            )

        launcher.place("+41791234567", subscriptionId = 2)

        assertEquals(emptyList<String>(), started)
        assertEquals(1, failures)
    }

    @Test
    fun tapToCallLauncher_callPhoneRevoked_reportsFailure() {
        val launcher =
            TapToCallLauncher(
                accountFor = { null },
                start = { _, _ -> throw SecurityException("CALL_PHONE revoked") },
                onFailure = { failures++ },
            )

        launcher.place("+41791234567", subscriptionId = 0)

        assertEquals(1, failures)
    }

    @Test
    fun tapToCallLauncher_permissionsHeld_startsCall() {
        val launcher = TapToCallLauncher({ null }, { address, _ -> started += address }, { failures++ })

        launcher.place("+41791234567", subscriptionId = 0)

        assertEquals(listOf("+41791234567"), started)
        assertEquals(0, failures)
    }

    @Test
    fun tapToCallLauncher_noAddress_doesNothing() {
        TapToCallLauncher(
            { null },
            { address, _ -> started += address },
            { failures++ },
        ).place(null, subscriptionId = 0)

        assertEquals(emptyList<String>(), started)
        assertEquals(0, failures)
    }
}
