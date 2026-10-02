package dev.tandem.feature.messaging

class RecordingSmsSender(
    private val partSize: Int = 153,
) : SmsSender {
    val sent = mutableListOf<OutgoingSms>()

    override fun divide(body: String): List<String> = body.chunked(partSize)

    override fun send(message: OutgoingSms) {
        sent += message
    }
}
