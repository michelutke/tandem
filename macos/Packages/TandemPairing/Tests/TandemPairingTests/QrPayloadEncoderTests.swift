import Foundation
import Testing
import TandemCrypto
@testable import TandemPairing

private enum TestError: Error {
    case invalidBase64
}

private func queryValue(for key: String, in uri: String) -> String? {
    guard let queryStart = uri.firstIndex(of: "?") else { return nil }
    let query = uri[uri.index(after: queryStart)...]
    for pair in query.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        guard parts.count == 2, parts[0] == Substring(key) else { continue }
        return String(parts[1])
    }
    return nil
}

private func base64URLDecode(_ value: String) throws -> Data {
    var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 {
        base64.append("=")
    }
    guard let data = Data(base64Encoded: base64) else {
        throw TestError.invalidBase64
    }
    return data
}

private func base64URLNoPadding(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func fixedFingerprint() throws -> SpkiFingerprint {
    try SpkiFingerprint(bytes: Data(repeating: 0xAB, count: SpkiFingerprint.byteCount))
}

@Test func qrPayloadEncoder_eachValidQrVectorFields_equalsVectorString() throws {
    let manifest = try QrPayloadVectorFixture.load()
    let validEntries = manifest.vectors.filter { $0.expected != nil }
    #expect(!validEntries.isEmpty)

    for entry in validEntries {
        guard let expected = entry.expected else { continue }
        let fingerprint = try SpkiFingerprint(bytes: try QrPayloadVectorFixture.hexDecode(expected.fingerprintHex))
        let secret = try QrPayloadVectorFixture.hexDecode(expected.secretHex)
        let nameBytes = try QrPayloadVectorFixture.hexDecode(expected.nameHex)
        // The vector's `nameHex` is fixture data, known-valid UTF-8 by construction.
        // swiftlint:disable:next optional_data_string_conversion
        let name = String(decoding: nameBytes, as: UTF8.self)

        let uri = QrPayloadEncoder.encode(
            fingerprint: fingerprint,
            secret: secret,
            addresses: expected.addresses,
            port: expected.port,
            name: name
        )

        #expect(uri == entry.input.uri, "vector \(entry.id)")
    }
}

@Test func qrPayload_twoWindowStarts_secretsDiffer() throws {
    let fingerprint = try fixedFingerprint()
    let addressSource = FakeLocalAddressSource(addresses: ["192.168.1.10"])

    let first = QrPayloadEncoder.generate(
        fingerprint: fingerprint,
        secretSource: SystemSecretSource(),
        addressSource: addressSource,
        port: 54321,
        name: "Mac"
    )
    let second = QrPayloadEncoder.generate(
        fingerprint: fingerprint,
        secretSource: SystemSecretSource(),
        addressSource: addressSource,
        port: 54321,
        name: "Mac"
    )

    #expect(first.secret != second.secret)
}

@Test func qrPayload_secretParam_decodesTo16Bytes() throws {
    let fingerprint = try fixedFingerprint()
    let payload = QrPayloadEncoder.generate(
        fingerprint: fingerprint,
        secretSource: SystemSecretSource(),
        addressSource: FakeLocalAddressSource(addresses: ["192.168.1.10"]),
        port: 54321,
        name: "Mac"
    )

    #expect(payload.secret.count == 16)

    let sParam = try #require(queryValue(for: "s", in: payload.uri))
    let decoded = try base64URLDecode(sParam)
    #expect(decoded.count == 16)
    #expect(decoded == payload.secret)
}

@Test func qrPayload_addressParam_equalsInjectedLocalAddresses() throws {
    let fingerprint = try fixedFingerprint()
    let injected = ["192.168.1.10", "2001:db8::1"]
    let payload = QrPayloadEncoder.generate(
        fingerprint: fingerprint,
        secretSource: SystemSecretSource(),
        addressSource: FakeLocalAddressSource(addresses: injected),
        port: 54321,
        name: "Mac"
    )

    let aParam = try #require(queryValue(for: "a", in: payload.uri))
    #expect(aParam == injected.joined(separator: ","))
}

@Test func qrPayload_generated_containsNoPrivateKeyBytes() throws {
    let fingerprintBytes = Data(repeating: 0xAB, count: SpkiFingerprint.byteCount)
    let fingerprint = try SpkiFingerprint(bytes: fingerprintBytes)
    let privateKeyLikeBytes = Data(repeating: 0xCD, count: 32)

    let payload = QrPayloadEncoder.generate(
        fingerprint: fingerprint,
        secretSource: SystemSecretSource(),
        addressSource: FakeLocalAddressSource(addresses: ["192.168.1.10"]),
        port: 54321,
        name: "Mac"
    )

    let fpParam = try #require(queryValue(for: "fp", in: payload.uri))
    #expect(fpParam == base64URLNoPadding(fingerprintBytes))
    #expect(!payload.uri.contains(privateKeyLikeBytes.map { String(format: "%02x", $0) }.joined()))
    #expect(!payload.uri.contains(base64URLNoPadding(privateKeyLikeBytes)))
}

@Test func qrPayload_moreThanEightInterfaces_firstEightRoutableAddressesOnly() throws {
    let fingerprint = try fixedFingerprint()
    let raw = [
        "127.0.0.1",
        "::1",
        "0.0.0.0",
        "::",
        "fe80::1",
        "10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4",
        "10.0.0.5", "10.0.0.6", "10.0.0.7", "10.0.0.8", "10.0.0.9"
    ]
    let payload = QrPayloadEncoder.generate(
        fingerprint: fingerprint,
        secretSource: SystemSecretSource(),
        addressSource: FakeLocalAddressSource(addresses: raw),
        port: 54321,
        name: "Mac"
    )

    let aParam = try #require(queryValue(for: "a", in: payload.uri))
    let expected = ["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4", "10.0.0.5", "10.0.0.6", "10.0.0.7", "10.0.0.8"]
    #expect(aParam == expected.joined(separator: ","))
}

@Test func qrPayload_macNameOver64Bytes_truncatedOnCodePointBoundary() throws {
    let fingerprint = try fixedFingerprint()
    // "é" is 2 UTF-8 bytes (0xC3 0xA9); 63 ASCII 'a's + "é" = 65 bytes, and a raw cut at byte 64
    // would land mid-scalar (splitting "é"'s two bytes).
    let name = String(repeating: "a", count: 63) + "é"
    #expect(name.utf8.count == 65)

    let payload = QrPayloadEncoder.generate(
        fingerprint: fingerprint,
        secretSource: SystemSecretSource(),
        addressSource: FakeLocalAddressSource(addresses: ["192.168.1.10"]),
        port: 54321,
        name: name
    )

    let nParam = try #require(queryValue(for: "n", in: payload.uri))
    let decodedName = try #require(nParam.removingPercentEncoding)
    #expect(decodedName.utf8.count <= 64)
    #expect(decodedName == String(repeating: "a", count: 63))
}
