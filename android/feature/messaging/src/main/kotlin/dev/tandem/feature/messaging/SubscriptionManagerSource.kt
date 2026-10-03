package dev.tandem.feature.messaging

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.telephony.SubscriptionManager
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/** [SubscriptionSource] over `SubscriptionManager`; READ_PHONE_STATE denied yields no subscriptions. */
class SubscriptionManagerSource(
    private val context: Context,
) : SubscriptionSource {
    private val manager: SubscriptionManager
        get() = context.getSystemService(SubscriptionManager::class.java)

    override fun activeSubscriptions(): List<SimInfo> {
        if (!phoneStateGranted()) return emptyList()
        return try {
            manager.activeSubscriptionInfoList.orEmpty().map {
                SimInfo(it.subscriptionId, it.displayName?.toString().orEmpty(), it.simSlotIndex)
            }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    override fun defaultSmsSubscriptionId(): Int {
        val id = SubscriptionManager.getDefaultSmsSubscriptionId()
        return if (SubscriptionManager.isValidSubscriptionId(id)) id else SubscriptionSource.NO_SUBSCRIPTION
    }

    override fun changes(): Flow<Unit> =
        callbackFlow {
            if (!phoneStateGranted()) {
                awaitClose {}
                return@callbackFlow
            }
            // The listener binds to the creating thread's Looper (the executor overload needs API 30).
            val main = Handler(Looper.getMainLooper())
            var listener: SubscriptionManager.OnSubscriptionsChangedListener? = null
            main.post {
                @Suppress("DEPRECATION")
                listener =
                    object : SubscriptionManager.OnSubscriptionsChangedListener() {
                        override fun onSubscriptionsChanged() {
                            trySend(Unit)
                        }
                    }.also { manager.addOnSubscriptionsChangedListener(it) }
            }
            awaitClose {
                main.post { listener?.let { manager.removeOnSubscriptionsChangedListener(it) } }
            }
        }

    private fun phoneStateGranted(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
}
