import VideoToolbox

public protocol DecoderCapabilityProbe: Sendable {
    func isHardwareDecodeSupported(_ codec: VideoCodec) -> Bool
}

public struct SystemDecoderCapabilityProbe: DecoderCapabilityProbe {
    public init() {}

    public func isHardwareDecodeSupported(_ codec: VideoCodec) -> Bool {
        switch codec {
        case .h264: VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        case .hevc: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        }
    }
}

public enum DecoderCapabilities {
    /// H.264 is the mandatory baseline; HEVC is advertised only with hardware decode (PRD F-9.1).
    public static func advertisedCodecs(probe: some DecoderCapabilityProbe) -> [VideoCodec] {
        probe.isHardwareDecodeSupported(.hevc) ? [.h264, .hevc] : [.h264]
    }
}
