import Testing
@testable import TandemProtocol

private let transferId = "0123456789abcdef"

@Test func macosFilenameSanitizer_pathTraversal_lastComponentOnly() throws {
    #expect(try FilenameSanitizer.sanitize("../../etc/passwd", transferId: transferId) == "passwd")
    #expect(try FilenameSanitizer.sanitize("C:\\dir\\a.txt", transferId: transferId) == "a.txt")
}

@Test func macosFilenameSanitizer_nulByte_invalidName() {
    #expect(throws: FilenameSanitizerError.invalidName) {
        try FilenameSanitizer.sanitize("a\u{0}b.txt", transferId: transferId)
    }
}

@Test func macosFilenameSanitizer_nfdInput_nfcOutput() throws {
    #expect(try FilenameSanitizer.sanitize("e\u{301}.txt", transferId: transferId) == "\u{E9}.txt")
}

@Test func macosFilenameSanitizer_bidiOverride_removed() throws {
    #expect(try FilenameSanitizer.sanitize("invoice\u{202E}fdp.exe", transferId: transferId) == "invoicefdp.exe")
}

@Test func macosFilenameSanitizer_emptyOrDotsOnly_usesTransferIdPrefix() throws {
    #expect(try FilenameSanitizer.sanitize("a/", transferId: transferId) == "file-01234567")
    #expect(try FilenameSanitizer.sanitize("...", transferId: transferId) == "file-01234567")
}

@Test func macosFilenameSanitizer_controlsAndColon_replacedWithUnderscore() throws {
    #expect(try FilenameSanitizer.sanitize("a:b\u{1}c\u{7F}d", transferId: transferId) == "a_b_c_d")
}

@Test func macosFilenameSanitizer_reservedStem_prefixed() throws {
    #expect(try FilenameSanitizer.sanitize("con.txt", transferId: transferId) == "_con.txt")
    #expect(try FilenameSanitizer.sanitize("LPT9", transferId: transferId) == "_LPT9")
    #expect(try FilenameSanitizer.sanitize("console.txt", transferId: transferId) == "console.txt")
}

@Test func macosFilenameSanitizer_overlongName_truncatedKeepingExtension() throws {
    let name = String(repeating: "\u{E9}", count: 200) + ".txt"
    let result = try FilenameSanitizer.sanitize(name, transferId: transferId)
    #expect(result.utf8.count <= 255)
    #expect(result.hasSuffix(".txt"))
}
