import CoreMedia
import Foundation
import Testing
@testable import FeatureMirror

private func fixtureData() throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: "h264-720p-30f", withExtension: "annexb", subdirectory: "Fixtures/media")
    )
    return try Data(contentsOf: url)
}

private struct FakeDecoderCapabilityProbe: DecoderCapabilityProbe {
    let hevc: Bool

    func isHardwareDecodeSupported(_ codec: VideoCodec) -> Bool {
        codec == .hevc ? hevc : true
    }
}

@Test func annexBParser_h264Fixture_splitsExpectedNalUnits() throws {
    let units = try AnnexBParser.parse(fixtureData())
    #expect(units.count == 33)
    #expect(units.prefix(4).map(\.h264Type) == [7, 8, 6, 5])
    #expect(units.dropFirst(4).allSatisfy { $0.h264Type == 1 })
}

@Test func annexBParser_threeAndFourByteStartCodes_bothRecognized() throws {
    let data = Data([0, 0, 0, 1, 0x67, 0xAA, 0, 0, 1, 0x68, 0xBB, 0xCC])
    let units = try AnnexBParser.parse(data)
    #expect(units.map(\.bytes) == [Data([0x67, 0xAA]), Data([0x68, 0xBB, 0xCC])])
}

@Test func annexBParser_malformedInput_rejected() {
    #expect(throws: AnnexBError.noStartCode) { try AnnexBParser.parse(Data()) }
    #expect(throws: AnnexBError.noStartCode) { try AnnexBParser.parse(Data([0, 0])) }
    #expect(throws: AnnexBError.noStartCode) { try AnnexBParser.parse(Data([0x67, 0, 0, 1, 0x68])) }
    #expect(throws: AnnexBError.zeroLengthNal) { try AnnexBParser.parse(Data([0, 0, 1])) }
    #expect(throws: AnnexBError.zeroLengthNal) { try AnnexBParser.parse(Data([0, 0, 1, 0x67, 0, 0, 1, 0, 0, 1, 0x68])) }
}

@Test func annexBParser_oversizeInput_rejected() {
    let huge = Data(count: AnnexBParser.maxInputBytes + 1)
    #expect(throws: AnnexBError.tooLarge) { try AnnexBParser.parse(huge) }
}

@Test func avccConverter_nalUnits_prefixedWithBigEndianLength() throws {
    let units = [NALUnit(bytes: Data([0x65, 1, 2])), NALUnit(bytes: Data(repeating: 0x41, count: 300))]
    let avcc = try AvccConverter.convert(units)
    #expect(avcc.prefix(7) == Data([0, 0, 0, 3, 0x65, 1, 2]))
    #expect(Array(avcc[7..<11]) == [0, 0, 1, 44])
    #expect(avcc.count == 7 + 4 + 300)
}

@Test func avccConverter_emptyNalUnit_rejected() {
    #expect(throws: AnnexBError.zeroLengthNal) { try AvccConverter.convert([NALUnit(bytes: Data())]) }
}

@Test func formatDescriptionBuilder_fixtureSpsPps_dimensions1280x720() throws {
    let units = try AnnexBParser.parse(fixtureData())
    let description = try FormatDescriptionBuilder.build(codec: .h264, nalUnits: units)
    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
    #expect(dimensions.width == 1280)
    #expect(dimensions.height == 720)
}

@Test func formatDescriptionBuilder_missingParameterSets_rejected() throws {
    let slices = try AnnexBParser.parse(fixtureData()).filter { $0.h264Type == 1 }
    #expect(throws: FormatDescriptionError.missingParameterSets) {
        try FormatDescriptionBuilder.build(codec: .h264, nalUnits: slices)
    }
}

@Test func decoderCapabilities_hevcHardwareUnavailable_advertisesH264Only() {
    #expect(DecoderCapabilities.advertisedCodecs(probe: FakeDecoderCapabilityProbe(hevc: false)) == [.h264])
    #expect(DecoderCapabilities.advertisedCodecs(probe: FakeDecoderCapabilityProbe(hevc: true)) == [.h264, .hevc])
}

private func fragment(
    _ reassembler: inout FragmentReassembler,
    pts: UInt64 = 1,
    index: UInt32,
    count: UInt32,
    _ bytes: [UInt8]
) throws -> Data? {
    try reassembler.accept(pts: pts, fragmentIndex: index, fragmentCount: count, data: Data(bytes))
}

@Test func fragmentReassembler_threeFragments_reassembledByteIdentical() throws {
    var reassembler = FragmentReassembler()
    #expect(try fragment(&reassembler, index: 0, count: 3, [1, 2]) == nil)
    #expect(try fragment(&reassembler, index: 1, count: 3, [3]) == nil)
    #expect(try fragment(&reassembler, index: 2, count: 3, [4, 5]) == Data([1, 2, 3, 4, 5]))
    #expect(try fragment(&reassembler, pts: 2, index: 0, count: 1, [9]) == Data([9]))
}

@Test func fragmentReassembler_violations_rejectedMalformedFrame() throws {
    var gap = FragmentReassembler()
    _ = try fragment(&gap, index: 0, count: 3, [1])
    #expect(throws: MediaFrameError.malformedFrame) { try fragment(&gap, index: 2, count: 3, [1]) }

    var firstNotZero = FragmentReassembler()
    #expect(throws: MediaFrameError.malformedFrame) { try fragment(&firstNotZero, index: 1, count: 3, [1]) }

    var countChange = FragmentReassembler()
    _ = try fragment(&countChange, index: 0, count: 3, [1])
    #expect(throws: MediaFrameError.malformedFrame) { try fragment(&countChange, index: 1, count: 2, [1]) }

    var tooMany = FragmentReassembler()
    #expect(throws: MediaFrameError.malformedFrame) { try fragment(&tooMany, index: 0, count: 9, [1]) }

    var zeroCount = FragmentReassembler()
    #expect(throws: MediaFrameError.malformedFrame) { try fragment(&zeroCount, index: 0, count: 0, [1]) }
}

@Test func fragmentReassembler_interleavedPts_rejectedMalformedFrame() throws {
    var reassembler = FragmentReassembler()
    _ = try fragment(&reassembler, pts: 1, index: 0, count: 2, [1])
    #expect(throws: MediaFrameError.malformedFrame) { try fragment(&reassembler, pts: 2, index: 0, count: 2, [1]) }
}

@Test func fragmentReassembler_totalOver8MiB_rejectedBeforeAllocation() throws {
    var reassembler = FragmentReassembler()
    let chunk = Data(count: 960 * 1024)
    for index in 0..<8 {
        _ = try reassembler.accept(pts: 1, fragmentIndex: UInt32(index), fragmentCount: 8, data: chunk)
    }
    var oversize = FragmentReassembler(maxBytes: 10)
    _ = try oversize.accept(pts: 1, fragmentIndex: 0, fragmentCount: 2, data: Data(count: 6))
    #expect(throws: MediaFrameError.malformedFrame) {
        try oversize.accept(pts: 1, fragmentIndex: 1, fragmentCount: 2, data: Data(count: 5))
    }
}

@Test func fragmentReassembler_fragmentOver960KiB_rejected() throws {
    var atLimit = FragmentReassembler()
    #expect(try atLimit.accept(pts: 1, fragmentIndex: 0, fragmentCount: 1, data: Data(count: 983_040)) != nil)

    var over = FragmentReassembler()
    #expect(throws: MediaFrameError.malformedFrame) {
        try over.accept(pts: 1, fragmentIndex: 0, fragmentCount: 1, data: Data(count: 983_041))
    }
}
