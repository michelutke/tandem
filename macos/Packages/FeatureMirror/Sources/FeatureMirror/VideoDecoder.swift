import CoreMedia
import Foundation
import VideoToolbox

public enum VideoDecodeError: Error, Equatable, Sendable {
    case sessionCreation(OSStatus)
    case invalidInput
    case decode(OSStatus)
    case noOutput
}

public protocol VideoDecoder {
    func decode(avcc: Data, pts: CMTime) throws(VideoDecodeError) -> CMSampleBuffer
    func invalidate()
}

public protocol SampleBufferSink {
    func enqueue(_ sampleBuffer: CMSampleBuffer)
}

public protocol KeyframeRequestSink {
    func requestKeyframe()
}

private final class DecodeOutput {
    var status: OSStatus = noErr
    var imageBuffer: CVImageBuffer?
}

/// Synchronous VTDecompressionSession wrapper: every `decode` returns once the frame is decoded.
public final class VTVideoDecoder: VideoDecoder {
    private let formatDescription: CMVideoFormatDescription
    private let session: VTDecompressionSession

    public init(formatDescription: CMVideoFormatDescription) throws(VideoDecodeError) {
        var created: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: nil,
            outputCallback: nil,
            decompressionSessionOut: &created
        )
        guard status == noErr, let created else { throw .sessionCreation(status) }
        self.formatDescription = formatDescription
        session = created
    }

    public func decode(avcc: Data, pts: CMTime) throws(VideoDecodeError) -> CMSampleBuffer {
        let input = try makeSampleBuffer(avcc: avcc, pts: pts)
        let output = DecodeOutput()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: input,
            flags: [],
            infoFlagsOut: nil
        ) { status, _, imageBuffer, _, _ in
            output.status = status
            output.imageBuffer = imageBuffer
        }
        guard status == noErr else { throw .decode(status) }
        guard output.status == noErr else { throw .decode(output.status) }
        guard let imageBuffer = output.imageBuffer else { throw .noOutput }
        return try makeDisplaySampleBuffer(imageBuffer: imageBuffer, pts: pts)
    }

    public func invalidate() {
        VTDecompressionSessionInvalidate(session)
    }

    private func makeSampleBuffer(avcc: Data, pts: CMTime) throws(VideoDecodeError) -> CMSampleBuffer {
        guard !avcc.isEmpty else { throw .invalidInput }
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &block
        )
        guard status == noErr, let block else { throw .invalidInput }
        status = avcc.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return OSStatus(kCMBlockBufferBadPointerParameterErr) }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }
        guard status == noErr else { throw .invalidInput }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var size = avcc.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: block,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw .invalidInput }
        return sample
    }

    private func makeDisplaySampleBuffer(
        imageBuffer: CVImageBuffer,
        pts: CMTime
    ) throws(VideoDecodeError) -> CMSampleBuffer {
        var description: CMVideoFormatDescription?
        let descriptionStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &description
        )
        guard descriptionStatus == noErr, let description else { throw .decode(descriptionStatus) }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            formatDescription: description,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw .decode(status) }
        return sample
    }
}
