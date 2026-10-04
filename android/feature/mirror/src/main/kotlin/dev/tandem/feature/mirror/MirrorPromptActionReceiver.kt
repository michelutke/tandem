package dev.tandem.feature.mirror

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Holds the live [MirrorPromptController] the prompt notification's actions are routed to. */
object MirrorPromptActionDispatcher {
    @Volatile
    var controller: MirrorPromptController? = null
}

/** Routes the prompt notification's Start/Not now/dismiss to [MirrorPromptActionDispatcher]'s controller. */
class MirrorPromptActionReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val controller = MirrorPromptActionDispatcher.controller ?: return
        when (intent.action) {
            NotificationMirrorPromptPresenter.ACTION_START -> controller.onStartTapped()
            NotificationMirrorPromptPresenter.ACTION_DECLINE -> controller.onDeclineOrDismiss()
        }
    }
}
