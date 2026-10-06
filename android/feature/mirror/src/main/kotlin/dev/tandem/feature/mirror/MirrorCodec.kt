package dev.tandem.feature.mirror

enum class MirrorCodec(
    val mimeType: String,
) {
    H264("video/avc"),
    Hevc("video/hevc"),
}
