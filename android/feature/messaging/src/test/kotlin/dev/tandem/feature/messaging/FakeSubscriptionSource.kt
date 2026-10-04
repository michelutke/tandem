package dev.tandem.feature.messaging

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeSubscriptionSource(
    var subscriptions: List<SimInfo> = emptyList(),
    var defaultSubscriptionId: Int = SubscriptionSource.NO_SUBSCRIPTION,
) : SubscriptionSource {
    private val changeEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    override fun activeSubscriptions(): List<SimInfo> = subscriptions

    override fun defaultSmsSubscriptionId(): Int = defaultSubscriptionId

    override fun changes(): Flow<Unit> = changeEvents

    fun emitChange() {
        changeEvents.tryEmit(Unit)
    }
}
