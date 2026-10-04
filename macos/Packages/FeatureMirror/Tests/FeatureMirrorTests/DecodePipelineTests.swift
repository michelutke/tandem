import CoreMedia
import Foundation
import Testing
@testable import FeatureMirror

private final class RecordingSink: SampleBufferSink {
    private(set) var presentationTimes: [CMTime] = []

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        presentationTimes.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}

private final class RecordingKeyframeRequests: KeyframeRequestSink {
    private(set) var count = 0

    func requestKeyframe() {
        count += 1
    }
}

private struct AccessUnit {
    let data: Data
    let isKeyframe: Bool
}

private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "annexb", subdirectory: "Fixtures/media")
    )
    return try Data(contentsOf: url)
}

private func accessUnits(_ name: String, codec: VideoCodec) throws -> [AccessUnit] {
    var units: [AccessUnit] = []
    var pending = Data()
    for nal in try AnnexBParser.parse(fixtureData(name)) {
        pending.append(contentsOf: [0, 0, 0, 1])
        pending.append(nal.bytes)
        let isSlice: Bool
        let isKey: Bool
        switch codec {
        case .h264:
            isSlice = nal.h264Type == 1 || nal.h264Type == 5
            isKey = nal.h264Type == 5
        case .hevc:
            isSlice = nal.hevcType <= 21
            isKey = nal.hevcType == 19 || nal.hevcType == 20
        }
        if isSlice {
            units.append(AccessUnit(data: pending, isKeyframe: isKey))
            pending = Data()
        }
    }
    return units
}

private func frameTime(_ index: Int) -> CMTime {
    CMTime(value: Int64(index) * 33_333, timescale: 1_000_000)
}

private func run(_ name: String, codec: VideoCodec) throws -> (RecordingSink, RecordingKeyframeRequests) {
    let sink = RecordingSink()
    let requests = RecordingKeyframeRequests()
    let pipeline = DecodePipeline(codec: codec, sink: sink, keyframeRequests: requests)
    for (index, unit) in try accessUnits(name, codec: codec).enumerated() {
        pipeline.submit(accessUnit: unit.data, pts: UInt64(frameTime(index).value), isKeyframe: unit.isKeyframe)
    }
    return (sink, requests)
}

@Test func decodePipeline_h264Fixture_delivers30FramesInPtsOrder() throws {
    let (sink, requests) = try run("h264-720p-30f", codec: .h264)
    #expect(sink.presentationTimes == (0..<30).map(frameTime))
    #expect(requests.count == 0)
}

@Test func decodePipeline_hevcFixture_delivers30FramesInPtsOrder() throws {
    let (sink, requests) = try run("hevc-720p-30f", codec: .hevc)
    #expect(sink.presentationTimes == (0..<30).map(frameTime))
    #expect(requests.count == 0)
}

@Test func decodePipeline_corruptedNalFixture_sendsOneKeyframeRequestWithoutCrash() throws {
    let (sink, requests) = try run("h264-720p-30f-corrupt", codec: .h264)
    #expect(requests.count == 1)
    #expect(sink.presentationTimes.count > 10)
    #expect(sink.presentationTimes == sink.presentationTimes.sorted())
}

@Test func decodePipeline_slicesBeforeFirstKeyframe_droppedWithoutRequest() throws {
    let sink = RecordingSink()
    let requests = RecordingKeyframeRequests()
    let pipeline = DecodePipeline(codec: .h264, sink: sink, keyframeRequests: requests)
    let units = try accessUnits("h264-720p-30f", codec: .h264)
    pipeline.submit(accessUnit: units[1].data, pts: 1, isKeyframe: false)
    pipeline.submit(accessUnit: units[0].data, pts: 2, isKeyframe: true)
    pipeline.submit(accessUnit: units[1].data, pts: 3, isKeyframe: false)
    #expect(sink.presentationTimes.map(\.value) == [2, 3])
    #expect(requests.count == 0)
}

@Test func decodePipeline_malformedInput_requestsKeyframeOnceAndSurvives() throws {
    let sink = RecordingSink()
    let requests = RecordingKeyframeRequests()
    let pipeline = DecodePipeline(codec: .h264, sink: sink, keyframeRequests: requests)
    pipeline.submit(accessUnit: Data([1, 2, 3]), pts: 1, isKeyframe: true)
    pipeline.submit(accessUnit: Data(), pts: 2, isKeyframe: false)
    pipeline.submit(accessUnit: Data([0, 0, 1, 0x67]), pts: 3, isKeyframe: true)
    pipeline.submit(accessUnit: Data([0, 0, 0, 1, 0x65, 0]), pts: UInt64.max, isKeyframe: true)
    #expect(requests.count == 1)
    #expect(sink.presentationTimes.isEmpty)
}

@Test func decodePipeline_keyframeDecodesAfterError_allowsNewRequest() throws {
    let sink = RecordingSink()
    let requests = RecordingKeyframeRequests()
    let pipeline = DecodePipeline(codec: .h264, sink: sink, keyframeRequests: requests)
    let units = try accessUnits("h264-720p-30f", codec: .h264)
    pipeline.submit(accessUnit: Data([1, 2, 3]), pts: 1, isKeyframe: true)
    pipeline.submit(accessUnit: units[0].data, pts: 2, isKeyframe: true)
    pipeline.submit(accessUnit: Data([1, 2, 3]), pts: 3, isKeyframe: false)
    #expect(requests.count == 2)
}

private final class CountingDecoder: VideoDecoder {
    nonisolated(unsafe) static var created = 0
    nonisolated(unsafe) static var invalidated = 0

    func decode(avcc: Data, pts: CMTime) throws(VideoDecodeError) -> CMSampleBuffer {
        throw .noOutput
    }

    func invalidate() {
        Self.invalidated += 1
    }
}

@Test func decodePipeline_newParameterSets_recreatesDecoder() throws {
    CountingDecoder.created = 0
    CountingDecoder.invalidated = 0
    let pipeline = DecodePipeline(
        codec: .h264,
        sink: RecordingSink(),
        keyframeRequests: RecordingKeyframeRequests()
    ) { _ throws(VideoDecodeError) in
        CountingDecoder.created += 1
        return CountingDecoder()
    }
    let first = try accessUnits("h264-720p-30f", codec: .h264)[0].data
    var changed = Data(first)
    let levelIdcOffset = 7
    changed[levelIdcOffset] ^= 0x01
    pipeline.submit(accessUnit: first, pts: 1, isKeyframe: true)
    pipeline.submit(accessUnit: first, pts: 2, isKeyframe: true)
    #expect(CountingDecoder.created == 1)
    pipeline.submit(accessUnit: changed, pts: 3, isKeyframe: true)
    #expect(CountingDecoder.created == 2)
    #expect(CountingDecoder.invalidated == 1)
}
