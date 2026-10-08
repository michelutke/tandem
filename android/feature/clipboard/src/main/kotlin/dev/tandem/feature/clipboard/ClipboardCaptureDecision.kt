package dev.tandem.feature.clipboard

import java.security.MessageDigest

/**
 * Whether a clip read by a capture path should be sent, shared by [ClipboardCaptureActivity] and
 * [OverlayCapture]. A missing clip, a sensitive clip and a missing session send nothing. An auto
 * capture also skips a clip identical to the last one it sent and an echo of a clip the Mac just
 * wrote ([loopGuard]); sending an auto capture records its hash in [LiveClipboardAutoCapture].
 */
class ClipboardCaptureDecision(
    private val loopGuard: ClipboardLoopGuard,
) {
    fun shouldSend(
        clip: ClipboardClip?,
        hasSession: Boolean,
        isAuto: Boolean,
    ): Boolean {
        val sendable = clip?.takeUnless { it.sensitive }
        return when {
            sendable == null || !hasSession -> false
            isAuto -> acceptAuto(sha256(sendable.text))
            else -> true
        }
    }

    private fun acceptAuto(hash: ByteArray): Boolean {
        val isRepeat = hash.contentEquals(LiveClipboardAutoCapture.lastSentHash)
        val accepted = !isRepeat && loopGuard.shouldSend(hash)
        if (accepted) LiveClipboardAutoCapture.lastSentHash = hash
        return accepted
    }

    private fun sha256(text: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
}
