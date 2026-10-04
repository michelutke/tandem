package dev.tandem.feature.messaging

/** One outgoing text, already divided into [parts]. Deliberately not a data class: no `toString` leak. */
class OutgoingSms(
    val clientMessageId: String,
    val destination: String,
    val subscriptionId: Int,
    val parts: List<String>,
)

/**
 * E50-04 feature-local seam over `SmsManager`: tests script it with `RecordingSmsSender`.
 * Per-part sent/delivery results arrive asynchronously through [SendResultBus].
 */
interface SmsSender {
    fun divide(body: String): List<String>

    fun send(message: OutgoingSms)
}

/** SEND_SMS grant check; [SendSmsHandler] never calls [SmsSender] while this is false. */
fun interface SendSmsPermission {
    fun isGranted(): Boolean
}
