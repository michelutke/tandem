package dev.tandem.feature.files

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** What the user is told about a send started from a share-sheet or in-app entry point. */
enum class SendFeedback {
    STARTED,
    SENT,
    REJECTED,
    FAILED,
    NOT_CONNECTED,
}

/**
 * The [FileSender] of the Ready session the send entry points ([ShareFilesActivity],
 * [PickFilesActivity]) hand files to. Set by the connection orchestrator's files feature while a
 * session is attached and cleared when it ends; the system constructs those activities, so they
 * read it through [starter]. No attached sender means [SendFeedback.NOT_CONNECTED].
 */
object LiveFileSession {
    private class Active(
        val sender: FileSender,
        val scope: CoroutineScope,
    )

    @Volatile
    private var active: Active? = null

    fun attach(
        sender: FileSender,
        scope: CoroutineScope,
    ) {
        active = Active(sender, scope)
    }

    fun detach(sender: FileSender) {
        if (active?.sender === sender) active = null
    }

    fun starter(feedback: (SendFeedback) -> Unit): TransferStarter =
        TransferStarter { request ->
            val current = active
            if (current == null) {
                feedback(SendFeedback.NOT_CONNECTED)
            } else {
                feedback(SendFeedback.STARTED)
                val state = current.sender.send(request)
                current.scope.launch {
                    feedback(state.first { it.isTerminal() }.toFeedback())
                }
            }
        }

    private fun SenderState.isTerminal(): Boolean =
        this is SenderState.Completed || this is SenderState.Rejected || this is SenderState.Cancelled

    private fun SenderState.toFeedback(): SendFeedback =
        when (this) {
            SenderState.Completed -> SendFeedback.SENT
            is SenderState.Rejected -> SendFeedback.REJECTED
            else -> SendFeedback.FAILED
        }
}
