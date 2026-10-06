package dev.tandem.feature.mirror

object EncoderConfigBuilder {
    private const val DEFAULT_WIDTH = 1920
    private const val DEFAULT_HEIGHT = 1080
    private const val DEFAULT_FRAME_RATE = 30
    private const val DEFAULT_BITRATE_BPS = 8_000_000
    private const val I_FRAME_INTERVAL_SECONDS = 2
    private const val REALTIME_PRIORITY = 0
    private const val LOW_LATENCY_ENABLED = 1

    fun build(
        width: Int = DEFAULT_WIDTH,
        height: Int = DEFAULT_HEIGHT,
        codec: MirrorCodec = MirrorCodec.H264,
    ): EncoderConfig =
        EncoderConfig(
            mimeType = codec.mimeType,
            width = width,
            height = height,
            frameRate = DEFAULT_FRAME_RATE,
            bitrateBitsPerSecond = DEFAULT_BITRATE_BPS,
            bitrateMode = EncoderBitrateMode.Cbr,
            profile = if (codec == MirrorCodec.Hevc) EncoderProfile.HevcMain else EncoderProfile.AvcConstrainedBaseline,
            level = if (codec == MirrorCodec.Hevc) EncoderLevel.HevcMain41 else EncoderLevel.Avc41,
            iFrameIntervalSeconds = I_FRAME_INTERVAL_SECONDS,
            priority = REALTIME_PRIORITY,
            lowLatency = LOW_LATENCY_ENABLED,
        )
}
