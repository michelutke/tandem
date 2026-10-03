import Foundation

/// One phone number of a cached contact. `number` is untrusted peer input and never logged
/// (invariant 7).
public struct ContactPhoneRecord: Sendable, Equatable {
    public let number: String
    public let normalizedE164: String

    public init(number: String, normalizedE164: String = "") {
        self.number = number
        self.normalizedE164 = normalizedE164
    }
}

/// A contact mirrored from the phone (`Contact`, SPEC § Contacts channel). `displayName`, numbers
/// and emails are untrusted peer input: sanitize before rendering, never log (invariant 7).
public struct ContactRecord: Sendable, Equatable {
    public let contactId: String
    public let displayName: String
    public let phoneNumbers: [ContactPhoneRecord]
    public let emails: [String]
    public let photoThumbnail: Data
    public let updatedAtMs: Int64

    public init(
        contactId: String,
        displayName: String,
        phoneNumbers: [ContactPhoneRecord],
        emails: [String] = [],
        photoThumbnail: Data = Data(),
        updatedAtMs: Int64
    ) {
        self.contactId = contactId
        self.displayName = displayName
        self.phoneNumbers = phoneNumbers
        self.emails = emails
        self.photoThumbnail = photoThumbnail
        self.updatedAtMs = updatedAtMs
    }
}
