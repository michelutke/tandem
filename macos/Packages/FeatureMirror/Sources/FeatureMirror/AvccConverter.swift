import Foundation

public enum AvccConverter {
    public static func convert(_ units: [NALUnit]) throws(AnnexBError) -> Data {
        var output = Data()
        for unit in units {
            guard !unit.bytes.isEmpty else { throw .zeroLengthNal }
            guard unit.bytes.count <= AnnexBParser.maxInputBytes,
                  output.count + 4 + unit.bytes.count <= AnnexBParser.maxInputBytes else { throw .tooLarge }
            let length = UInt32(unit.bytes.count)
            output.append(contentsOf: [24, 16, 8, 0].map { UInt8((length >> $0) & 0xFF) })
            output.append(unit.bytes)
        }
        return output
    }
}
