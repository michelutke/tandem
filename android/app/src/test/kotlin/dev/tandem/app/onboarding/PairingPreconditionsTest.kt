package dev.tandem.app.onboarding

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// E20-14 tdd: unit: pairingPreconditions_allOptionalPermissionsDenied_pairingAllowed
class PairingPreconditionsTest {
    @Test
    fun pairingPreconditions_allOptionalPermissionsDenied_pairingAllowed() {
        // isPairingAllowed takes no permission state at all: notification-listener access,
        // POST_NOTIFICATIONS and the battery-optimization exemption being denied changes nothing.
        assertTrue(PairingPreconditions.isPairingAllowed())
    }
}
