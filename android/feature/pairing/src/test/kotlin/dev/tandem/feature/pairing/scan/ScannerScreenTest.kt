package dev.tandem.feature.pairing.scan

import android.Manifest
import android.app.Application
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.pairing.qr.PairingInvite
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E14-10 tdd:
//   ui: scannerScreen_cameraPermissionDenied_showsCameraPermissionRequired
//   ui: scannerScreen_acceptedScan_navigatesToPairingProgress
// Compose `ui:` tests under Robolectric (E00-20); no camera involved in either case.
private const val VALID_TANDEM_QR =
    "tandem://pair?v=1&fp=bIeynz76iy05sAK-bVNEV5vcrEO5uQuuYQq6FJhTzUI&s=s1M4FPXbKtRZFFn8dntlVw" +
        "&a=192.168.1.10&p=54321&n=Michel%27s%20MacBook%20Pro"

@RunWith(AndroidJUnit4::class)
class ScannerScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun scannerScreen_cameraPermissionDenied_showsCameraPermissionRequired() {
        // Fresh Robolectric application: the CAMERA permission is denied by default.
        composeRule.setContent {
            ScannerScreen(onScanAccepted = {}, onCancel = {})
        }

        composeRule.onNodeWithText("Camera needed.").assertExists()
        composeRule.onNodeWithText("Grant").assertExists()
    }

    @Test
    fun scannerScreen_acceptedScan_navigatesToPairingProgress() {
        shadowOf(ApplicationProvider.getApplicationContext<Application>()).grantPermissions(Manifest.permission.CAMERA)
        var acceptedInvite: PairingInvite? = null

        composeRule.setContent {
            ScannerScreen(
                onScanAccepted = { invite -> acceptedInvite = invite },
                onCancel = {},
                frameSource = { onResult ->
                    LaunchedEffect(Unit) {
                        onResult(ScanResult(format = ScanFormat.QR_CODE, rawValue = VALID_TANDEM_QR))
                    }
                },
            )
        }

        composeRule.waitForIdle()

        assertNotNull("expected onScanAccepted to have navigated to the pairing-progress screen", acceptedInvite)
        assertEquals("Michel's MacBook Pro", acceptedInvite?.macName)
    }
}
