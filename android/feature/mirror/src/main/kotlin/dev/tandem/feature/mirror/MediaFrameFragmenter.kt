package dev.tandem.feature.mirror

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.MediaFrame
import dev.tandem.protocol.v1.mediaFrame

/** SPEC.md #media-frame-semantics: splits one access unit into at most 8 fragments of at most 960 KiB. */
object MediaFrameFragmenter {
    const val MAX_FRAGMENT_BYTES = 960 * 1024
    const val MAX_FRAGMENTS = 8
    const val FLAG_KEYFRAME = 0x1
    const val FLAG_CODEC_CONFIG = 0x2

    /** Returns null when the access unit would need more than [MAX_FRAGMENTS] fragments. */
    fun fragment(
        accessUnit: ByteArray,
        ptsMicros: Long,
        flags: Int,
    ): List<MediaFrame>? {
        val count = maxOf(1, (accessUnit.size + MAX_FRAGMENT_BYTES - 1) / MAX_FRAGMENT_BYTES)
        if (count > MAX_FRAGMENTS) return null
        return List(count) { index ->
            val start = index * MAX_FRAGMENT_BYTES
            val end = minOf(accessUnit.size, start + MAX_FRAGMENT_BYTES)
            mediaFrame {
                pts = ptsMicros
                this.flags = flags
                data = ByteString.copyFrom(accessUnit, start, end - start)
                fragmentIndex = index
                fragmentCount = count
            }
        }
    }
}
