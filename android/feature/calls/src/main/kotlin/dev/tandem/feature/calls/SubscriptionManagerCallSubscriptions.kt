package dev.tandem.feature.calls

import android.content.Context
import android.telephony.SubscriptionManager

/** Production [CallSubscriptions]; without READ_PHONE_STATE no subscription is visible, so none is active. */
class SubscriptionManagerCallSubscriptions(
    private val context: Context,
) : CallSubscriptions {
    override fun isActive(subscriptionId: Int): Boolean =
        try {
            context
                .getSystemService(SubscriptionManager::class.java)
                .getActiveSubscriptionInfo(subscriptionId) != null
        } catch (_: SecurityException) {
            false
        }
}
