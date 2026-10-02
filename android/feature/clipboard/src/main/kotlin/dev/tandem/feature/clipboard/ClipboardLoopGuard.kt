package dev.tandem.feature.clipboard

/**
 * E31-08: Android half of clipboard echo-loop prevention (macOS half: E31-14). Remember the most
 * recently received `(originTag, contentHash)` before writing it to the local clipboard
 * ([recordReceived]); [shouldSend] then suppresses a locally detected change whose hash matches
 * it, so a Mac to phone to Mac echo never starts. The record is cleared once a different local
 * change is sent, so re-copying the same content later is sent normally.
 */
class ClipboardLoopGuard {
    private class Received(
        val originTag: String,
        val contentHash: ByteArray,
    )

    private var lastReceived: Received? = null

    @Synchronized
    fun recordReceived(
        originTag: String,
        contentHash: ByteArray,
    ) {
        lastReceived = Received(originTag, contentHash.copyOf())
    }

    @Synchronized
    fun shouldSend(contentHash: ByteArray): Boolean {
        val received = lastReceived
        if (received != null && received.contentHash.contentEquals(contentHash)) return false
        lastReceived = null
        return true
    }
}
