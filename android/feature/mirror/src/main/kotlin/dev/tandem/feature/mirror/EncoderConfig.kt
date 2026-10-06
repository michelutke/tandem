package dev.tandem.feature.mirror

enum class EncoderBitrateMode {
    Cbr,
}

enum class EncoderProfile {
    AvcConstrainedBaseline,
    HevcMain,
}

enum class EncoderLevel {
    Avc41,
    HevcMain41,
}

/** Platform-neutral encoder settings; the E61-03 adapter maps them onto `android.media.MediaFormat`. */
data class EncoderConfig(
    val mimeType: String,
    val width: Int,
    val height: Int,
    val frameRate: Int,
    val bitrateBitsPerSecond: Int,
    val bitrateMode: EncoderBitrateMode,
    val profile: EncoderProfile,
    val level: EncoderLevel,
    val iFrameIntervalSeconds: Int,
    val priority: Int,
    val lowLatency: Int?,
)
