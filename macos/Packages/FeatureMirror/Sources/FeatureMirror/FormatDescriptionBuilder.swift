import CoreMedia
import Foundation

public enum FormatDescriptionError: Error, Equatable, Sendable {
    case missingParameterSets
    case coreMediaFailure(OSStatus)
}

public enum FormatDescriptionBuilder {
    public static func build(
        codec: VideoCodec,
        nalUnits: [NALUnit]
    ) throws(FormatDescriptionError) -> CMVideoFormatDescription {
        switch codec {
        case .h264:
            try create(parameterSets: pick(nalUnits, types: [7, 8], typeOf: \.h264Type), codec: .h264)
        case .hevc:
            try create(parameterSets: pick(nalUnits, types: [32, 33, 34], typeOf: \.hevcType), codec: .hevc)
        }
    }

    private static func pick(
        _ units: [NALUnit],
        types: [UInt8],
        typeOf: KeyPath<NALUnit, UInt8>
    ) throws(FormatDescriptionError) -> [Data] {
        var sets: [Data] = []
        for type in types {
            guard let unit = units.first(where: { $0[keyPath: typeOf] == type }) else { throw .missingParameterSets }
            sets.append(unit.bytes)
        }
        return sets
    }

    private static func create(
        parameterSets: [Data],
        codec: VideoCodec
    ) throws(FormatDescriptionError) -> CMVideoFormatDescription {
        var description: CMVideoFormatDescription?
        var status: OSStatus = noErr
        withParameterSetPointers(parameterSets) { pointers, sizes in
            switch codec {
            case .h264:
                status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil,
                    parameterSetCount: pointers.count,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description
                )
            case .hevc:
                status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: nil,
                    parameterSetCount: pointers.count,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    extensions: nil,
                    formatDescriptionOut: &description
                )
            }
        }
        guard status == noErr, let description else { throw .coreMediaFailure(status) }
        return description
    }

    private static func withParameterSetPointers(
        _ sets: [Data],
        _ body: ([UnsafePointer<UInt8>], [Int]) -> Void
    ) {
        let copies = sets.map { [UInt8]($0) }
        func recurse(_ index: Int, _ pointers: [UnsafePointer<UInt8>]) {
            guard index < copies.count else {
                body(pointers, copies.map(\.count))
                return
            }
            copies[index].withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                recurse(index + 1, pointers + [base])
            }
        }
        recurse(0, [])
    }
}
