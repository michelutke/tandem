package dev.tandem.feature.messaging

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.SimListKt
import dev.tandem.protocol.v1.simList
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * E50-05 publishes `SimList` on the SMS channel at session start and whenever [SubscriptionSource]
 * reports a change, so the Mac shows a SIM picker only with 2+ active SIMs. [log] receives counts
 * only, never carrier names (invariant 7).
 */
class SimListPublisher(
    private val subscriptions: SubscriptionSource,
    private val session: TandemSession,
    private val ioDispatcher: CoroutineDispatcher,
    private val log: (String) -> Unit = {},
) {
    suspend fun run() {
        coroutineScope {
            val pending = KtChannel<Unit>(KtChannel.CONFLATED)
            launch(start = CoroutineStart.UNDISPATCHED) {
                subscriptions.changes().collect { pending.trySend(Unit) }
            }
            publish()
            pending.receiveAsFlow().collect { publish() }
        }
    }

    private suspend fun publish() {
        val active = withContext(ioDispatcher) { subscriptions.activeSubscriptions() }
        session.send(Channel.CHANNEL_SMS) {
            simList =
                simList {
                    active.forEach { sim ->
                        subscriptions +=
                            SimListKt.subscription {
                                subscriptionId = sim.subscriptionId
                                displayName = sim.displayName
                                slotIndex = sim.slotIndex
                            }
                    }
                }
        }
        log("sim list: published count=${active.size}")
    }
}
