import Foundation

private struct FilenamesVectorInput: Decodable {
    let rawUtf8Hex: String
    let transferId: String
}

private struct FilenamesVectorExpected: Decodable {
    let filename: String
}

private struct FilenamesVector: Decodable {
    let id: String
    let input: FilenamesVectorInput
    let expected: FilenamesVectorExpected?
    let expectedError: String?
}

private struct FilenamesManifest: Decodable {
    let vectors: [FilenamesVector]
}

/// `filenames` category handler for ``ConformanceRunner`` (E40-02): applies the reference
/// implementation of docs/protocol/SPEC.md `#filename-sanitization` below to each vector's raw name.
extension ConformanceRunner {
    static let invalidNameError = "invalidName"

    static func runFilenames(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(FilenamesManifest.self, from: data)
        return try manifest.vectors.map { vector in
            let raw = try conformanceRunnerHexDecode(vector.input.rawUtf8Hex)
            guard let name = String(data: raw, encoding: .utf8) else {
                throw ConformanceFailure(description: "filenames vector \(vector.id) is not valid UTF-8")
            }
            let expected = vector.expectedError ?? vector.expected?.filename ?? ""
            let actual = sanitizeFilename(name, transferId: vector.input.transferId) ?? invalidNameError
            return VectorOutcome(
                id: vector.id, category: "filenames", outcome: actual == expected ? "pass" : "fail",
                expected: expected, actual: actual
            )
        }
    }

    private static let maxFilenameBytes = 255
    private static let windowsReservedStems: Set<String> = Set(
        ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
    )

    private static func sanitizeFilename(_ name: String, transferId: String) -> String? {
        let scalars = name.unicodeScalars
        if scalars.contains(where: { $0.value == 0 }) {
            return nil
        }
        let components = scalars.split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "\\" }
        let lastComponent = components.last.map { String(String.UnicodeScalarView($0)) } ?? ""
        var text = String.UnicodeScalarView(
            lastComponent.precomposedStringWithCanonicalMapping.unicodeScalars.compactMap(replacingUnsafe)
        )
        while text.first == "." {
            text.removeFirst()
        }
        if text.isEmpty {
            return "file-\(transferId.prefix(8))"
        }
        var filename = String(text)
        let stem = filename.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
        if windowsReservedStems.contains(stem.uppercased()) {
            filename = "_" + filename
        }
        return truncateToFilenameLimit(filename)
    }

    private static func replacingUnsafe(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069: return nil
        case 0x00...0x1F, 0x7F, 0x3A: return "_"
        default: return scalar
        }
    }

    private static func truncateToFilenameLimit(_ name: String) -> String {
        guard name.utf8.count > maxFilenameBytes else {
            return name
        }
        var stem = Array(name.unicodeScalars)
        var extensionScalars: [Unicode.Scalar] = []
        if let dot = stem.lastIndex(of: "."), dot > 0 {
            extensionScalars = Array(stem[dot...])
            stem = Array(stem[..<dot])
        }
        var budget = maxFilenameBytes - String(String.UnicodeScalarView(extensionScalars)).utf8.count
        if budget < 1 {
            stem = Array(name.unicodeScalars)
            extensionScalars = []
            budget = maxFilenameBytes
        }
        var kept = String.UnicodeScalarView()
        var used = 0
        for scalar in stem {
            let size = String(scalar).utf8.count
            if used + size > budget {
                break
            }
            kept.append(scalar)
            used += size
        }
        kept.append(contentsOf: extensionScalars)
        return String(kept)
    }
}
