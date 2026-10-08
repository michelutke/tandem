package dev.tandem.feature.calls

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import dev.tandem.core.ui.TandemActivity

/**
 * Invisible trampoline behind the "Tap to call" notification (E52-05): the tap is the user action
 * that lets `ACTION_CALL` start from here. Not exported: reached only by the explicit-component
 * PendingIntent [NotificationTapToCallNotifier] builds.
 */
class TapToCallActivity : TandemActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val address = intent.getStringExtra(EXTRA_ADDRESS)
        if (!address.isNullOrEmpty()) {
            val call =
                Intent(Intent.ACTION_CALL, Uri.fromParts("tel", address, null)).apply {
                    callAccountFor(
                        getSystemService(TelephonyManager::class.java),
                        getSystemService(TelecomManager::class.java),
                        intent.getIntExtra(EXTRA_SUBSCRIPTION_ID, 0),
                    )?.let { putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, it) }
                }
            startActivity(call)
        }
        finish()
    }

    companion object {
        const val EXTRA_ADDRESS = "address"
        const val EXTRA_SUBSCRIPTION_ID = "subscriptionId"
    }
}
