package dev.tandem.feature.messaging

class RecordingSmsSender(
    private val partSize: Int = 153,
) : SmsSender {
    val sent = mutableListOf<OutgoingSms>()
    var failNextWith: RuntimeException? = null

    override fun divide(body: String): List<String> = body.chunked(partSize)

    override fun send(message: OutgoingSms) {
        failNextWith?.let {
            failNextWith = null
            throw it
        }
        sent += message
    }
}
