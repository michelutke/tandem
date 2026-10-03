package dev.tandem.feature.files

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Holds the live [AcceptFlow] the prompt's notification actions are routed to. */
object TransferActionDispatcher {
    @Volatile
    var acceptFlow: AcceptFlow? = null
}

/** Routes the prompt notification's Accept/Decline taps to [TransferActionDispatcher]'s [AcceptFlow]. */
class TransferActionReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val offerId = intent.getStringExtra(NotificationTransferPrompter.EXTRA_OFFER_ID) ?: return
        val flow = TransferActionDispatcher.acceptFlow ?: return
        when (intent.action) {
            NotificationTransferPrompter.ACTION_ACCEPT -> flow.accept(offerId)
            NotificationTransferPrompter.ACTION_DECLINE -> flow.decline(offerId)
        }
    }
}
