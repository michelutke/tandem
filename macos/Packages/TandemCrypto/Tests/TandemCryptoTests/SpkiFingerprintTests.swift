import Foundation
import Testing
@testable import TandemCrypto

@Test func spkiFingerprint_everyFingerprintVector_matchesExpectedSha256() throws {
    let manifest = try SpkiFingerprintVectorFixture.load()
    let positiveEntries = manifest.vectors.filter { $0.expected != nil }
    let negativeEntries = manifest.vectors.filter { $0.expectedError != nil }

    #expect(!positiveEntries.isEmpty)
    #expect(!negativeEntries.isEmpty)

    for entry in positiveEntries {
        guard let expected = entry.expected else { continue }
        let spkiDer = try SpkiFingerprintVectorFixture.spkiDer(for: entry)
        let fingerprint = try SpkiFingerprint.compute(spkiDer: spkiDer)
        let fingerprintHex = fingerprint.map { String(format: "%02x", $0) }.joined()
        #expect(fingerprintHex == expected.fingerprintHex, "vector \(entry.id)")
    }

    for entry in negativeEntries {
        guard let expectedErrorName = entry.expectedError else { continue }
        let expectedError = try validationError(named: expectedErrorName, vectorId: entry.id)
        let spkiDer = try SpkiFingerprintVectorFixture.spkiDer(for: entry)

        do {
            _ = try SpkiFingerprint.compute(spkiDer: spkiDer)
            Issue.record("vector \(entry.id) expected \(expectedErrorName) but did not throw")
        } catch let error as SpkiFingerprint.ValidationError {
            #expect(error == expectedError, "vector \(entry.id)")
        } catch {
            Issue.record("vector \(entry.id) threw unexpected error type \(error)")
        }
    }
}

@Test func spkiFingerprint_twoDecodesOfSameCert_identical32Bytes() throws {
    let manifest = try SpkiFingerprintVectorFixture.load()
    let entry = try #require(manifest.vectors.first { $0.expected != nil })

    let firstDecode = try SpkiFingerprintVectorFixture.spkiDer(for: entry)
    let secondDecode = try SpkiFingerprintVectorFixture.spkiDer(for: entry)

    let firstFingerprint = try SpkiFingerprint.compute(spkiDer: firstDecode)
    let secondFingerprint = try SpkiFingerprint.compute(spkiDer: secondDecode)

    #expect(firstFingerprint.count == 32)
    #expect(constantTimeEquals(firstFingerprint, secondFingerprint))
}

@Test func spkiFingerprint_stringForm_is43CharsBase64UrlNoPadding() throws {
    let manifest = try SpkiFingerprintVectorFixture.load()
    let entry = try #require(manifest.vectors.first { $0.expected != nil })
    let spkiDer = try SpkiFingerprintVectorFixture.spkiDer(for: entry)

    let stringForm = try SpkiFingerprint.computeBase64URLString(spkiDer: spkiDer)

    #expect(stringForm.count == 43)
    #expect(!stringForm.contains("="))
    #expect(!stringForm.contains("+"))
    #expect(!stringForm.contains("/"))
}

@Test func spkiFingerprint_differentPublicKey_differentFingerprint() throws {
    let manifest = try SpkiFingerprintVectorFixture.load()
    let positiveEntries = manifest.vectors.filter { $0.expected != nil }
    let firstEntry = try #require(positiveEntries.first)
    let secondEntry = try #require(positiveEntries.dropFirst().first)

    let firstSpkiDer = try SpkiFingerprintVectorFixture.spkiDer(for: firstEntry)
    let secondSpkiDer = try SpkiFingerprintVectorFixture.spkiDer(for: secondEntry)

    let firstFingerprint = try SpkiFingerprint.compute(spkiDer: firstSpkiDer)
    let secondFingerprint = try SpkiFingerprint.compute(spkiDer: secondSpkiDer)

    #expect(constantTimeEquals(firstFingerprint, secondFingerprint) == false)
}

@Test func spkiFingerprint_expectedByteCount_is91AndMatchesPositiveVector() throws {
    let manifest = try SpkiFingerprintVectorFixture.load()
    let entry = try #require(manifest.vectors.first { $0.expected != nil })
    let spkiDer = try SpkiFingerprintVectorFixture.spkiDer(for: entry)

    #expect(SpkiFingerprint.expectedSpkiDerByteCount == 91)
    #expect(spkiDer.count == SpkiFingerprint.expectedSpkiDerByteCount)
}

private func validationError(
    named name: String,
    vectorId: String
) throws -> SpkiFingerprint.ValidationError {
    switch name {
    case "unsupportedPointEncoding":
        return .unsupportedPointEncoding
    case "unsupportedKeyType":
        return .unsupportedKeyType
    case "malformedSpki":
        return .malformedSpki
    default:
        throw SpkiFingerprintVectorFixture.LoadError(
            description: "vector \(vectorId) has unknown expectedError \(name)"
        )
    }
}
