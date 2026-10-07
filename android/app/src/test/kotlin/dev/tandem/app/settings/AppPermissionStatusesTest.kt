package dev.tandem.app.settings

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class AppPermissionStatusesTest {
    @Test
    fun statuses_nothingGranted_listsEveryPermissionOff() {
        val statuses = RecordingPermissionGateway().statuses()

        assertEquals(AppPermission.entries, statuses.map { it.permission })
        assertEquals(List(AppPermission.entries.size) { false }, statuses.map { it.granted })
    }

    @Test
    fun statuses_someGranted_marksOnlyThoseOn() {
        val gateway = RecordingPermissionGateway(mutableSetOf(AppPermission.CAMERA, AppPermission.SMS))

        val granted = gateway.statuses().filter { it.granted }.map { it.permission }

        assertEquals(listOf(AppPermission.SMS, AppPermission.CAMERA), granted)
    }

    @Test
    fun appPermission_labels_areUnique() {
        assertEquals(
            AppPermission.entries.size,
            AppPermission.entries
                .map { it.label }
                .toSet()
                .size,
        )
    }
}
