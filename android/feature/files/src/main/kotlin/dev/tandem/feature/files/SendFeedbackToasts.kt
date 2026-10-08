package dev.tandem.feature.files

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.Toast

/** Shows [SendFeedback] as toasts (ui-spec.md §9.4); never names the file (invariant 7). */
internal object SendFeedbackToasts {
    fun liveStarter(
        context: Context,
        onFinished: (SendRequest) -> Unit = {},
    ): TransferStarter {
        val mainHandler = Handler(Looper.getMainLooper())
        return LiveFileSession.starter(onFinished) { feedback ->
            mainHandler.post { Toast.makeText(context, message(context, feedback), Toast.LENGTH_SHORT).show() }
        }
    }

    private fun message(
        context: Context,
        feedback: SendFeedback,
    ): String =
        context.getString(
            when (feedback) {
                SendFeedback.STARTED -> R.string.files_send_started
                SendFeedback.SENT -> R.string.files_send_sent
                SendFeedback.REJECTED -> R.string.files_send_rejected
                SendFeedback.FAILED -> R.string.files_send_failed
                SendFeedback.NOT_CONNECTED -> R.string.files_send_not_connected
            },
        )
}
