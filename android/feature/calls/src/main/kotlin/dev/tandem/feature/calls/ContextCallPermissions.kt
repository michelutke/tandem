package dev.tandem.feature.calls

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager

class ContextCallPermissions(
    private val context: Context,
) : CallPermissions {
    override fun readPhoneState(): Boolean = granted(Manifest.permission.READ_PHONE_STATE)

    override fun answerPhoneCalls(): Boolean = granted(Manifest.permission.ANSWER_PHONE_CALLS)

    override fun callPhone(): Boolean = granted(Manifest.permission.CALL_PHONE)

    private fun granted(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
}
