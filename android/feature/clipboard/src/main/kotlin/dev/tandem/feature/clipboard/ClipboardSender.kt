package dev.tandem.feature.clipboard

import com.google.protobuf.ByteString
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.clipboardText
import java.security.MessageDigest

/**
 * E31-06: shared Android clipboard sender, the counterpart to macOS's `ClipboardSender`
 * (`macos/Packages/FeatureClipboard/Sources/FeatureClipboard/ClipboardSender.swift`). Reused by
 * [ShareTargetActivity] and [ProcessTextActivity] here, and by the future foreground-capture
 * (E31-07) and quick-settings-tile (E31-12) entry points.
 *
 * docs/protocol/SPEC.md #clipboard-channel "Size limit", restated from #10
 * (`#timeouts-connection-limits-and-resource-caps`, E01-22) "Feature caps": `text` MUST be at most
 * [MAX_TEXT_BYTES] (1 MiB, 2^20) of UTF-8; an over-cap [send] rejects the text outright, never
 * truncating it, and never sends a frame.
 */
object ClipboardSender {
    /** docs/protocol/SPEC.md #clipboard-channel "Size limit". */
    const val MAX_TEXT_BYTES = 1_048_576

    /** UC-13: the message shown when [send] rejects text over [MAX_TEXT_BYTES]. */
    const val TOO_LARGE_TOAST = "Text too large to send (max 1 MiB)"

    private const val ORIGIN_TAG = "android"

    /**
     * Sends [text] as a `ClipboardText` (originTag = "android") on [session]'s CLIPBOARD channel
     * if [text]'s UTF-8 byte length is at most [MAX_TEXT_BYTES]; returns `true`. Otherwise sends
     * nothing, calls [onTooLarge], and returns `false`.
     *
     * [onTooLarge] is a callback rather than a direct `Toast` call so this object stays
     * unit-testable (under Robolectric or plain JUnit) without a real UI `Context` -- a caller that
     * needs to show a toast (e.g. [ShareTargetActivity]) wires this to `Toast.makeText` itself.
     *
     * [sensitive] (E31-07) is carried straight onto `ClipboardText.sensitive` -- set it `true` only
     * when the caller has already decided this content is sensitive and still wants it sent (e.g.
     * the user explicitly tapped an in-app "Send clipboard to Mac" button); a passive capture path
     * must never send a sensitive clip at all rather than send it with this flag set.
     */
    suspend fun send(
        text: String,
        session: TandemSession,
        sensitive: Boolean = false,
        onTooLarge: () -> Unit = {},
    ): Boolean {
        val utf8Bytes = text.toByteArray(Charsets.UTF_8)
        if (utf8Bytes.size > MAX_TEXT_BYTES) {
            onTooLarge()
            return false
        }

        val contentHash = MessageDigest.getInstance("SHA-256").digest(utf8Bytes)
        session.send(Channel.CHANNEL_CLIPBOARD) {
            clipboardText =
                clipboardText {
                    originTag = ORIGIN_TAG
                    this.contentHash = ByteString.copyFrom(contentHash)
                    this.text = text
                    this.sensitive = sensitive
                }
        }
        return true
    }
}
