package dev.tandem.feature.messaging

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

enum class SendResultKind { SENT, DELIVERED }

/** One part's `SmsManager` sent or delivery result, as reported by a PendingIntent broadcast. */
class PartResult(
    val clientMessageId: String,
    val partIndex: Int,
    val kind: SendResultKind,
    val resultCode: Int,
)

/** Process-wide hand-off from [SendResultReceiver] to the in-flight [SendSmsHandler] sends. */
object SendResultBus {
    private val mutableResults = MutableSharedFlow<PartResult>(extraBufferCapacity = BUFFER)
    val results: SharedFlow<PartResult> = mutableResults

    fun publish(result: PartResult) {
        mutableResults.tryEmit(result)
    }

    private const val BUFFER = 256
}
