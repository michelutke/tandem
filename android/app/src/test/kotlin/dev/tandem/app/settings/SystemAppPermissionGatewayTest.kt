package dev.tandem.app.settings

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Intent
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.feature.input.AccessibilityStateSource
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf

@RunWith(AndroidJUnit4::class)
class SystemAppPermissionGatewayTest {
    private val application = ApplicationProvider.getApplicationContext<Application>()
    private val launched = mutableListOf<Array<String>>()
    private var accessibilityOn = false
    private var callScreeningRoleHeld = false
    private var roleRequests = 0
    private val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    private val gateway =
        SystemAppPermissionGateway(
            activity,
            requestRuntimePermissions = { launched += it },
            accessibilityState =
                object : AccessibilityStateSource {
                    override fun isServiceEnabled(): Boolean = accessibilityOn
                },
            isCallScreeningRoleHeld = { callScreeningRoleHeld },
            requestCallScreeningRole = { roleRequests++ },
        )

    @Test
    fun isGranted_runtimePermissionGrantedInSystem_isOn() {
        assertFalse(gateway.isGranted(AppPermission.CAMERA))

        shadowOf(application).grantPermissions(Manifest.permission.CAMERA)

        assertTrue(gateway.isGranted(AppPermission.CAMERA))
    }

    @Test
    fun isGranted_smsNeedsBothReadAndSend() {
        shadowOf(application).grantPermissions(Manifest.permission.READ_SMS)
        assertFalse(gateway.isGranted(AppPermission.SMS))

        shadowOf(application).grantPermissions(Manifest.permission.SEND_SMS)

        assertTrue(gateway.isGranted(AppPermission.SMS))
    }

    @Test
    fun isGranted_phoneNeedsStateAnswerAndCallPermissions() {
        shadowOf(application).grantPermissions(Manifest.permission.READ_PHONE_STATE, Manifest.permission.CALL_PHONE)
        assertFalse(gateway.isGranted(AppPermission.PHONE))

        shadowOf(application).grantPermissions(Manifest.permission.ANSWER_PHONE_CALLS)

        assertTrue(gateway.isGranted(AppPermission.PHONE))
    }

    @Test
    fun isGranted_callerIdFollowsCallScreeningRole() {
        assertFalse(gateway.isGranted(AppPermission.CALLER_ID))

        callScreeningRoleHeld = true

        assertTrue(gateway.isGranted(AppPermission.CALLER_ID))
    }

    @Test
    fun request_callerIdRoleNotHeld_requestsRole() {
        gateway.request(AppPermission.CALLER_ID)

        assertEquals(1, roleRequests)
    }

    @Test
    fun request_callerIdRoleHeld_opensDefaultAppsSettings() {
        callScreeningRoleHeld = true

        gateway.request(AppPermission.CALLER_ID)

        assertEquals(0, roleRequests)
        assertEquals(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS, nextStartedAction())
    }

    @Test
    fun isGranted_accessibilityFollowsServiceState() {
        assertFalse(gateway.isGranted(AppPermission.ACCESSIBILITY))

        accessibilityOn = true

        assertTrue(gateway.isGranted(AppPermission.ACCESSIBILITY))
    }

    @Test
    fun request_runtimePermissionFirstTime_launchesSystemDialog() {
        gateway.request(AppPermission.SMS)

        assertEquals(1, launched.size)
        assertArrayEquals(arrayOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS), launched.single())
    }

    @Test
    fun request_runtimePermissionDeniedBefore_opensAppDetailsSettings() {
        gateway.request(AppPermission.CONTACTS)

        gateway.request(AppPermission.CONTACTS)

        assertEquals(1, launched.size)
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, nextStartedAction())
    }

    @Test
    fun request_notificationAccess_opensListenerSettings() {
        gateway.request(AppPermission.NOTIFICATION_ACCESS)

        assertEquals(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS, nextStartedAction())
    }

    @Test
    fun request_batteryNotExempt_opensExemptionDialog() {
        gateway.request(AppPermission.BATTERY)

        assertEquals(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, nextStartedAction())
    }

    @Test
    fun request_accessibility_opensAccessibilitySettings() {
        gateway.request(AppPermission.ACCESSIBILITY)

        assertEquals(Settings.ACTION_ACCESSIBILITY_SETTINGS, nextStartedAction())
    }

    private fun nextStartedAction(): String? {
        val intent: Intent? = shadowOf(activity).nextStartedActivity
        return intent?.action
    }
}
