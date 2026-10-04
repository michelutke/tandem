package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.mediaHello
import java.nio.ByteBuffer
import java.security.SecureRandom

/** What a `MEDIAOPEN` scenario presents on the media connection (E60-05). */
internal sealed class MediaPresentation {
    /** A `MediaHello` carrying no ticket. */
    data object NoTicket : MediaPresentation()

    /** An mTLS-complete connection that sends nothing at all. */
    data object Silent : MediaPresentation()

    class Ticket(
        val bytes: ByteArray,
    ) : MediaPresentation()
}

/**
 * Builds the raw first frames behind the `RAWTICKET`/`MEDIAOPEN` commands (E60-05 mitm-lab media
 * ticket scenarios): a `MediaHello` with a caller-chosen ticket, so a scenario can present a missing,
 * reused, expired, ended-session or other-peer ticket that the real `MediaDialer` never would.
 */
internal object RawMedia {
    private const val MIRROR_SESSION_ID_BYTES = 16
    private const val LENGTH_PREFIX_BYTES = 4

    /** `NONE`, `SILENT`, or ticket hex; `null` for anything else. */
    fun parsePresentation(arg: String): MediaPresentation? =
        when (arg.uppercase()) {
            "NONE" -> MediaPresentation.NoTicket
            "SILENT" -> MediaPresentation.Silent
            else -> arg.decodeHexOrNull()?.let { MediaPresentation.Ticket(it) }
        }

    fun helloFrame(
        ticket: ByteArray?,
        mirrorSessionId: ByteArray = SecureRandom().generateSeed(MIRROR_SESSION_ID_BYTES),
    ): ByteArray {
        val body =
            mediaHello {
                if (ticket != null) this.ticket = ByteString.copyFrom(ticket)
                this.mirrorSessionId = ByteString.copyFrom(mirrorSessionId)
            }.toByteArray()
        return ByteBuffer
            .allocate(LENGTH_PREFIX_BYTES + body.size)
            .putInt(body.size)
            .put(body)
            .array()
    }

    private fun String.decodeHexOrNull(): ByteArray? {
        if (length % 2 != 0 || isEmpty()) return null
        return runCatching {
            ByteArray(length / 2) { i -> ((this[2 * i].digitToInt(16) shl 4) or this[2 * i + 1].digitToInt(16)).toByte() }
        }.getOrNull()
    }
}
