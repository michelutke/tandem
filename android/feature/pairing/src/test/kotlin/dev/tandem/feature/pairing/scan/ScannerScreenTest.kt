package dev.tandem.feature.pairing.scan

import android.Manifest
import android.app.Application
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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

    private fun showWithFrames(
        vararg values: String,
        onCancel: () -> Unit = {},
    ) {
        shadowOf(ApplicationProvider.getApplicationContext<Application>()).grantPermissions(Manifest.permission.CAMERA)
        composeRule.setContent {
            ScannerScreen(
                onScanAccepted = {},
                onCancel = onCancel,
                frameSource = { onResult ->
                    LaunchedEffect(Unit) {
                        values.forEach { onResult(ScanResult(format = ScanFormat.QR_CODE, rawValue = it)) }
                    }
                },
            )
        }
        composeRule.waitForIdle()
    }

    @Test
    fun scannerScreen_nonTandemQr_showsNotATandemCode() {
        showWithFrames("https://example.com")

        composeRule.onNodeWithText("Not a Tandem code.").assertExists()
        composeRule.onNodeWithText("Or it was already used.").assertExists()
        composeRule.onNodeWithText("Show a fresh code on your Mac: Pair phone.").assertExists()
        composeRule.onNodeWithText("Scan again").assertExists()
    }

    @Test
    fun scannerScreen_rejectedTandemCode_showsNotATandemCode() {
        showWithFrames("tandem://pair?v=1&bogus")

        composeRule.onNodeWithText("Not a Tandem code.").assertExists()
    }

    @Test
    fun scannerScreen_scanAgainTapped_returnsToScanning() {
        showWithFrames("https://example.com")

        composeRule.onNodeWithText("Scan again").performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("Scan.").assertExists()
        composeRule.onNodeWithText("Decoded on this phone. Nothing is uploaded.").assertExists()
    }

    @Test
    fun scannerScreen_scanning_cancelCallsOnCancel() {
        var cancels = 0
        showWithFrames(onCancel = { cancels++ })

        composeRule.onNodeWithText("Cancel").performClick()

        assertEquals(1, cancels)
    }
}
