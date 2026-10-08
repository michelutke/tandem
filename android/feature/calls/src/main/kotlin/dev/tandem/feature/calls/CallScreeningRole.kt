package dev.tandem.feature.calls

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent

/** The call-screening role (`RoleManager.ROLE_CALL_SCREENING`) that lets [TandemCallScreeningService] run. */
object CallScreeningRole {
    fun isHeld(context: Context): Boolean {
        val roles = context.getSystemService(RoleManager::class.java)
        return roles.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
            roles.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
    }

    /** The system dialog asking the user to grant the role; must be started for a result. */
    fun requestIntent(context: Context): Intent =
        context.getSystemService(RoleManager::class.java).createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING)
}
