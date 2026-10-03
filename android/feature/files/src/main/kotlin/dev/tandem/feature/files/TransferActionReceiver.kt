package dev.tandem.feature.files

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Holds the live [AcceptFlow] the prompt's notification actions are routed to. */
object TransferActionDispatcher {
    @Volatile
    var acceptFlow: AcceptFlow? = null

    /** Cancels the in-flight transfer with the given id (E40-12). */
    @Volatile
    var cancelTransfer: ((String) -> Unit)? = null
}

/** Routes the prompt notification's Accept/Decline taps to [TransferActionDispatcher]'s [AcceptFlow]. */
class TransferActionReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val offerId = intent.getStringExtra(NotificationTransferPrompter.EXTRA_OFFER_ID) ?: return
        when (intent.action) {
            TransferProgressNotifier.ACTION_CANCEL -> TransferActionDispatcher.cancelTransfer?.invoke(offerId)
            NotificationTransferPrompter.ACTION_ACCEPT -> TransferActionDispatcher.acceptFlow?.accept(offerId)
            NotificationTransferPrompter.ACTION_DECLINE -> TransferActionDispatcher.acceptFlow?.decline(offerId)
        }
    }
}
