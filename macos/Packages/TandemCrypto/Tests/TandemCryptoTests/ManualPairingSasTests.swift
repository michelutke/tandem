import Foundation
import Testing
@testable import TandemCrypto

private struct ManualVectors: Decodable {
    struct Entry: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }

    struct Input: Decodable {
        let kind: String
        let noncePhoneHex: String?
        let nonceMacHex: String?
        let macSpkiDerHex: String?
        let phoneSpkiDerHex: String?
        let cbHex: String?
        let committerRole: String?
        let commitmentHex: String?
        let revealNonceHex: String?
    }

    struct Expected: Decodable {
        let commitPhoneHex: String?
        let commitMacHex: String?
        let sas: String?
    }

    let vectors: [Entry]

    static func load() throws -> ManualVectors {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/manual-pairing.json")
        return try JSONDecoder().decode(ManualVectors.self, from: Data(contentsOf: url))
    }
}

private func bytes(_ hex: String?) -> Data {
    var data = Data()
    var index = (hex ?? "").startIndex
    while index < (hex ?? "").endIndex {
        let next = (hex ?? "").index(index, offsetBy: 2)
        data.append(UInt8((hex ?? "")[index..<next], radix: 16) ?? 0)
        index = next
    }
    return data
}

private func context(_ input: ManualVectors.Input) -> ManualPairingSas.Context {
    ManualPairingSas.Context(
        macSpkiDer: bytes(input.macSpkiDerHex), phoneSpkiDer: bytes(input.phoneSpkiDerHex),
        channelBinding: bytes(input.cbHex)
    )
}

@Test func manualPairingSas_everySasVector_derivesExpectedCommitmentsAndSixDigits() throws {
    let entries = try ManualVectors.load().vectors.filter { $0.input.kind == "sas" }
    #expect(!entries.isEmpty)
    for entry in entries {
        let input = entry.input
        let sas = try ManualPairingSas.sas(
            noncePhone: bytes(input.noncePhoneHex), nonceMac: bytes(input.nonceMacHex), context: context(input)
        )
        let commitPhone = try ManualPairingSas.commitment(
            role: .phone, nonce: bytes(input.noncePhoneHex), context: context(input)
        )
        let commitMac = try ManualPairingSas.commitment(
            role: .mac, nonce: bytes(input.nonceMacHex), context: context(input)
        )
        #expect(sas == entry.expected?.sas, "\(entry.id)")
        #expect(commitPhone == bytes(entry.expected?.commitPhoneHex), "\(entry.id)")
        #expect(commitMac == bytes(entry.expected?.commitMacHex), "\(entry.id)")
    }
}

@Test func manualPairingSas_everyCommitmentVector_verifiesOnlyMatchingReveals() throws {
    let entries = try ManualVectors.load().vectors.filter { $0.input.kind == "commitment" }
    #expect(!entries.isEmpty)
    for entry in entries {
        let input = entry.input
        let verified = ManualPairingSas.verifyCommitment(
            bytes(input.commitmentHex),
            role: input.committerRole == "phone" ? .phone : .mac,
            revealedNonce: bytes(input.revealNonceHex),
            context: context(input)
        )
        #expect(verified == (entry.expectedError == nil), "\(entry.id)")
    }
}

@Test func manualPairingSas_malformedNonce_throwsAndNeverVerifies() throws {
    let entry = try #require(ManualVectors.load().vectors.first { $0.input.kind == "sas" })
    let input = entry.input
    let short = Data(count: 15)
    #expect(throws: ManualPairingSas.ValidationError.malformedNonce) {
        try ManualPairingSas.sas(noncePhone: short, nonceMac: bytes(input.nonceMacHex), context: context(input))
    }
    #expect(!ManualPairingSas.verifyCommitment(
        Data(count: 32), role: .phone, revealedNonce: short, context: context(input)
    ))
}
