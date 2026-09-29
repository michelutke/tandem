import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `contacts-encoding` category handler for ``ConformanceRunner`` (E51-01): decodes the raw
/// message bytes each vector describes (`input.messageHex`, or `input.thumbnailRecipe` for the
/// oversized-thumbnail vector -- see `protocol/vectors/README.md`) with the real generated
/// CONTACTS message types, selected by `input.kind`. `contact` vectors are additionally validated
/// against the CONTACTS channel's 32,768-byte `photo_thumbnail` cap via the real
/// `ContactThumbnailValidator`, not just asserted at the vector level. Deliberately does not go
/// through `FrameEncoder`/`FrameDecoder`, for the same reason `files-encoding.json` does not (see
/// `ConformanceRunner+Files.swift`).
extension ConformanceRunner {
    /// JSON `CONTACT_ADDRESS_TYPE_*` name -> wire number, matching `tools/vectors/contacts_encoding.py`.
    static let contactAddressTypeNumbers: [String: Int] = [
        "CONTACT_ADDRESS_TYPE_UNSPECIFIED": 0,
        "CONTACT_ADDRESS_TYPE_HOME": 1,
        "CONTACT_ADDRESS_TYPE_WORK": 2,
        "CONTACT_ADDRESS_TYPE_MOBILE": 3,
        "CONTACT_ADDRESS_TYPE_OTHER": 4
    ]

    /// JSON `CONTACTS_SYNC_STATUS_*` name -> wire number, matching `tools/vectors/contacts_encoding.py`.
    static let contactsSyncStatusNumbers: [String: Int] = [
        "CONTACTS_SYNC_STATUS_UNSPECIFIED": 0,
        "CONTACTS_SYNC_STATUS_OK": 1,
        "CONTACTS_SYNC_STATUS_PERMISSION_REQUIRED": 2,
        "CONTACTS_SYNC_STATUS_FULL_RESYNC_REQUIRED": 3
    ]

    static func runContactsEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(ContactsEncodingManifest.self, from: data)
        return try manifest.vectors.map { try contactsEncodingOutcome($0) }
    }

    private static func contactsEncodingOutcome(_ vector: ContactsEncodingManifest.Vector) throws -> VectorOutcome {
        switch vector.input.kind {
        case "contact": return try contactOutcome(vector)
        case "contactsSyncRequest": return try contactsSyncRequestOutcome(vector)
        case "contactsSyncResponse": return try contactsSyncResponseOutcome(vector)
        default:
            throw ConformanceFailure(description: "unsupported contacts-encoding kind: \(vector.input.kind)")
        }
    }

    private static func contactBytes(_ input: ContactsEncodingManifest.Input) throws -> Data {
        if let hex = input.messageHex {
            return try conformanceRunnerHexDecode(hex)
        }
        guard let recipe = input.thumbnailRecipe else {
            throw ConformanceFailure(description: "contacts-encoding contact vector missing thumbnailRecipe")
        }
        let fillByte = try conformanceRunnerHexDecode(recipe.fillByte)
        guard let byte = fillByte.first else {
            throw ConformanceFailure(description: "thumbnailRecipe.fillByte must be one byte")
        }
        var message = Tandem_V1_Contact()
        message.photoThumbnail = Data(repeating: byte, count: recipe.fillLength)
        return try message.serializedData()
    }

    private static func contactOutcome(_ vector: ContactsEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try contactBytes(vector.input)
        guard let decoded = try? Tandem_V1_Contact(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "contacts-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        let accepted = ContactThumbnailValidator.isValid(decoded.photoThumbnail)

        if let expected = vector.expected {
            guard accepted else {
                return VectorOutcome(
                    id: vector.id, category: "contacts-encoding", outcome: "fail",
                    expected: "accepted", actual: "rejected: contactPhotoThumbnailTooLarge"
                )
            }
            return try contactValidOutcome(vector.id, expected, decoded)
        }
        guard let expectedError = vector.expectedError else {
            throw ConformanceFailure(description: "vector \(vector.id) has neither expected nor expectedError")
        }
        let actual = accepted ? "accepted" : "contactPhotoThumbnailTooLarge"
        return VectorOutcome(
            id: vector.id, category: "contacts-encoding",
            outcome: actual == expectedError ? "pass" : "fail",
            expected: expectedError, actual: actual
        )
    }

    private static func contactValidOutcome(
        _ id: String,
        _ expected: ContactsEncodingManifest.Expected,
        _ decoded: Tandem_V1_Contact
    ) throws -> VectorOutcome {
        guard let expectedContactId = expected.contactId, let expectedDisplayName = expected.displayName,
              let expectedPhotoThumbnailHex = expected.photoThumbnailHex,
              let expectedUpdatedAtMs = expected.updatedAtMs,
              let expectedPhoneNumbers = expected.phoneNumbers, let expectedEmails = expected.emails else {
            throw ConformanceFailure(description: "contacts-encoding vector \(id) missing expected fields")
        }

        let phoneNumbersMatch = decoded.phoneNumbers.count == expectedPhoneNumbers.count
            && zip(decoded.phoneNumbers, expectedPhoneNumbers).allSatisfy { actual, expected in
                actual.number == expected.number && actual.normalizedE164 == expected.normalizedE164
                    && actual.type.rawValue == contactAddressTypeNumbers[expected.type]
            }
        let emailsMatch = decoded.emails.count == expectedEmails.count
            && zip(decoded.emails, expectedEmails).allSatisfy { actual, expected in
                actual.address == expected.address && actual.type.rawValue == contactAddressTypeNumbers[expected.type]
            }

        let passed = decoded.contactID == expectedContactId && decoded.displayName == expectedDisplayName
            && decoded.photoThumbnail.conformanceRunnerHex == expectedPhotoThumbnailHex
            && decoded.updatedAtMs == expectedUpdatedAtMs && phoneNumbersMatch && emailsMatch
        return VectorOutcome(
            id: id, category: "contacts-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "contactId=\(expectedContactId) displayName=\(expectedDisplayName)",
            actual: "contactId=\(decoded.contactID) displayName=\(decoded.displayName)"
        )
    }

    private static func contactsSyncRequestOutcome(_ vector: ContactsEncodingManifest.Vector) throws -> VectorOutcome {
        guard let hex = vector.input.messageHex else {
            throw ConformanceFailure(description: "contacts-encoding vector \(vector.id) missing messageHex")
        }
        let bytes = try conformanceRunnerHexDecode(hex)
        guard let decoded = try? Tandem_V1_ContactsSyncRequest(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "contacts-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expectedSinceUpdatedAtMs = vector.expected?.sinceUpdatedAtMs else {
            throw ConformanceFailure(description: "contacts-encoding vector \(vector.id) missing expected fields")
        }
        let passed = decoded.sinceUpdatedAtMs == expectedSinceUpdatedAtMs
        return VectorOutcome(
            id: vector.id, category: "contacts-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "sinceUpdatedAtMs=\(expectedSinceUpdatedAtMs)",
            actual: "sinceUpdatedAtMs=\(decoded.sinceUpdatedAtMs)"
        )
    }

    private static func contactsSyncResponseOutcome(_ vector: ContactsEncodingManifest.Vector) throws -> VectorOutcome {
        guard let hex = vector.input.messageHex else {
            throw ConformanceFailure(description: "contacts-encoding vector \(vector.id) missing messageHex")
        }
        let bytes = try conformanceRunnerHexDecode(hex)
        guard let decoded = try? Tandem_V1_ContactsSyncResponse(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "contacts-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expected = vector.expected, let expectedStatusName = expected.status,
              let expectedStatusNumber = contactsSyncStatusNumbers[expectedStatusName],
              let expectedContactCount = expected.contactCount, let expectedDeletedIds = expected.deletedContactIds,
              let expectedWatermarkMs = expected.watermarkMs, let expectedComplete = expected.complete else {
            throw ConformanceFailure(description: "contacts-encoding vector \(vector.id) missing expected fields")
        }
        let passed = decoded.status.rawValue == expectedStatusNumber
            && decoded.contacts.count == expectedContactCount
            && decoded.deletedContactIds == expectedDeletedIds
            && decoded.watermarkMs == expectedWatermarkMs
            && decoded.complete == expectedComplete
        return VectorOutcome(
            id: vector.id, category: "contacts-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "status=\(expectedStatusName) deletedContactIds=\(expectedDeletedIds)",
            actual: "status=\(decoded.status.rawValue) deletedContactIds=\(decoded.deletedContactIds)"
        )
    }
}

struct ContactsEncodingManifest: Decodable {
    struct ThumbnailRecipe: Decodable {
        let fillByte: String
        let fillLength: Int
    }
    struct Input: Decodable {
        let kind: String
        let messageHex: String?
        let thumbnailRecipe: ThumbnailRecipe?
    }
    struct ExpectedPhoneNumber: Decodable {
        let number: String
        let normalizedE164: String
        let type: String
    }
    struct ExpectedEmail: Decodable {
        let address: String
        let type: String
    }
    struct Expected: Decodable {
        let contactId: String?
        let displayName: String?
        let phoneNumbers: [ExpectedPhoneNumber]?
        let emails: [ExpectedEmail]?
        let photoThumbnailHex: String?
        let updatedAtMs: UInt64?
        let contactSha256: String?
        let sinceUpdatedAtMs: UInt64?
        let status: String?
        let contactCount: Int?
        let deletedContactIds: [String]?
        let watermarkMs: UInt64?
        let complete: Bool?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }
    let vectors: [Vector]
}
