package dev.tandem.feature.messaging

import kotlinx.coroutines.flow.Flow

/** One active SIM. Deliberately not a data class: no `toString` leak of the carrier name. */
class SimInfo(
    val subscriptionId: Int,
    val displayName: String,
    val slotIndex: Int,
)

/**
 * E50-05 feature-local seam over `SubscriptionManager`. A denied READ_PHONE_STATE yields an empty
 * [activeSubscriptions] and [NO_SUBSCRIPTION] as the default.
 */
interface SubscriptionSource {
    fun activeSubscriptions(): List<SimInfo>

    /** The default SMS subscription id, or [NO_SUBSCRIPTION] when none is valid. */
    fun defaultSmsSubscriptionId(): Int

    /** Emits once per `OnSubscriptionsChangedListener` callback. */
    fun changes(): Flow<Unit>

    companion object {
        const val NO_SUBSCRIPTION = -1
    }
}
