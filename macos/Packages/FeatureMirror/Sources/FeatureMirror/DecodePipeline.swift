import CoreMedia
import Foundation

/// Turns reassembled Annex-B access units into decoded sample buffers. The input is untrusted:
/// anything malformed is dropped and answered with at most one `KeyframeRequest` until a keyframe
/// decodes again. Not thread-safe; call from one serial context.
public final class DecodePipeline {
    public typealias DecoderFactory = (CMVideoFormatDescription) throws(VideoDecodeError) -> any VideoDecoder

    private var codec: VideoCodec
    private let sink: any SampleBufferSink
    private let keyframeRequests: any KeyframeRequestSink
    private let makeDecoder: DecoderFactory
    private var decoder: (any VideoDecoder)?
    private var parameterSets: [Data] = []
    private var awaitingKeyframe = true
    private var keyframeRequested = false

    public init(
        codec: VideoCodec,
        sink: any SampleBufferSink,
        keyframeRequests: any KeyframeRequestSink,
        makeDecoder: @escaping DecoderFactory = { description throws(VideoDecodeError) in
            try VTVideoDecoder(formatDescription: description)
        }
    ) {
        self.codec = codec
        self.sink = sink
        self.keyframeRequests = keyframeRequests
        self.makeDecoder = makeDecoder
    }

    deinit {
        decoder?.invalidate()
    }

    public func reset(codec: VideoCodec) {
        self.codec = codec
        discardDecoder()
    }

    public func submit(accessUnit: Data, pts: UInt64, isKeyframe: Bool) {
        guard let units = try? AnnexBParser.parse(accessUnit), let time = presentationTime(pts) else {
            requestKeyframeOnce()
            return
        }
        let sets = units.filter(isParameterSet)
        if !sets.isEmpty, !applyParameterSets(sets, in: units) { return }
        let slices = units.filter { !isParameterSet($0) }
        guard let decoder, !slices.isEmpty else { return }
        if awaitingKeyframe {
            guard isKeyframe else { return }
        }
        decode(slices, pts: time, isKeyframe: isKeyframe, with: decoder)
    }

    private func decode(_ slices: [NALUnit], pts: CMTime, isKeyframe: Bool, with decoder: any VideoDecoder) {
        do {
            let sample = try decoder.decode(avcc: AvccConverter.convert(slices), pts: pts)
            if isKeyframe {
                awaitingKeyframe = false
                keyframeRequested = false
            }
            sink.enqueue(sample)
        } catch {
            requestKeyframeOnce()
        }
    }

    /// Returns false when the new parameter sets could not be applied.
    private func applyParameterSets(_ sets: [NALUnit], in units: [NALUnit]) -> Bool {
        let bytes = sets.map(\.bytes)
        guard bytes != parameterSets else { return true }
        do {
            let description = try FormatDescriptionBuilder.build(codec: codec, nalUnits: units)
            let newDecoder = try makeDecoder(description)
            discardDecoder()
            decoder = newDecoder
            parameterSets = bytes
            return true
        } catch {
            requestKeyframeOnce()
            return false
        }
    }

    private func discardDecoder() {
        decoder?.invalidate()
        decoder = nil
        parameterSets = []
        awaitingKeyframe = true
    }

    private func requestKeyframeOnce() {
        guard !keyframeRequested else { return }
        keyframeRequested = true
        keyframeRequests.requestKeyframe()
    }

    private func presentationTime(_ pts: UInt64) -> CMTime? {
        Int64(exactly: pts).map { CMTime(value: $0, timescale: 1_000_000) }
    }

    private func isParameterSet(_ unit: NALUnit) -> Bool {
        switch codec {
        case .h264: [7, 8].contains(unit.h264Type)
        case .hevc: [32, 33, 34].contains(unit.hevcType)
        }
    }
}
