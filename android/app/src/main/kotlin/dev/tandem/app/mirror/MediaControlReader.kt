package dev.tandem.app.mirror

import dev.tandem.protocol.v1.MediaMessage
import java.io.DataInputStream
import java.io.IOException
import java.io.InputStream

/**
 * Reads the Mac -> phone `MediaMessage`s on the media connection (SPEC.md #media-frame-semantics)
 * and routes `KeyframeRequest` to [onKeyframeRequest]. Returns on end of stream, an I/O error, an
 * oversize frame or an undecodable one, so the caller can close the media connection. Frame
 * content is never logged (invariant 7).
 */
class MediaControlReader(
    input: InputStream,
    private val onKeyframeRequest: () -> Unit,
) {
    private val input = DataInputStream(input)

    fun run() {
        try {
            while (true) {
                val length = input.readInt()
                if (length !in 1..MAX_FRAME_BYTES) return
                val message = MediaMessage.parseFrom(ByteArray(length).also(input::readFully))
                if (message.hasKeyframeRequest()) onKeyframeRequest()
            }
        } catch (_: IOException) {
            return
        }
    }

    private companion object {
        const val MAX_FRAME_BYTES = 1024 * 1024
    }
}
