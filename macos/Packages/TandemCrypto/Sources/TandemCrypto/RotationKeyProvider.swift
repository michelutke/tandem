#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Security

/// Both signatures and the new SPKI a `KeyRotation` frame carries (SPEC.md #key-rotation).
public struct SignedRotation: Sendable, Equatable {
    public let newSpkiDer: Data
    public let sigOldKey: Data
    public let sigNewKey: Data
}

/// Initiator-side key handling for a key rotation (E70-03): the pending identity key lives in the
/// inactive ``IdentityKeySlots`` tag beside the active identity key until every paired phone has
/// acked, then ``promote(pendingTag:)`` switches the active slot. Reaches the Keychain only through
/// `KeychainStore` (E10-16); it is the only place outside `IdentityKeyProvider` that touches a raw
/// `SecKey`, so the `key_material_only_in_crypto` lint rule (E10-14) stays satisfied.
public struct RotationKeyProvider: Sendable {
    private static let signingAlgorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256

    private let keychainStore: any KeychainStore
    private let slots: IdentityKeySlots

    public init(keychainStore: any KeychainStore) {
        self.keychainStore = keychainStore
        self.slots = IdentityKeySlots(keychainStore: keychainStore)
    }

    /// SPKI DER of the active identity key. Throws `KeychainError.itemNotFound` if none exists;
    /// never creates one.
    public func activeSpkiDer() throws -> Data {
        try Self.spkiDer(of: keychainStore.copyKey(tag: slots.activeTag()))
    }

    /// The tag the pending key is (or will be) stored under.
    public func pendingTag() throws -> String {
        try slots.inactiveTag()
    }

    /// SPKI DER of the pending key, generating it (same accessibility class as the identity key)
    /// if none exists yet. An existing pending key is reused, never replaced.
    public func getOrCreatePendingSpkiDer() throws -> Data {
        let tag = try slots.inactiveTag()
        do {
            return try Self.spkiDer(of: keychainStore.copyKey(tag: tag))
        } catch KeychainError.itemNotFound {
            return try Self.spkiDer(of: keychainStore.addKey(tag: tag, accessibility: .afterFirstUnlockThisDeviceOnly))
        }
    }

    /// Signs the E70-01 transcript (active SPKI, pending SPKI, `challenge`) with the active and
    /// the pending private key.
    public func sign(challenge: Data) throws -> SignedRotation {
        let oldKey = try keychainStore.copyKey(tag: slots.activeTag())
        let newKey = try keychainStore.copyKey(tag: slots.inactiveTag())
        let oldSpki = try Self.spkiDer(of: oldKey)
        let newSpki = try Self.spkiDer(of: newKey)
        let transcript = RotationVerifier.transcript(oldSpkiDer: oldSpki, newSpkiDer: newSpki, challenge: challenge)
        return SignedRotation(
            newSpkiDer: newSpki,
            sigOldKey: try Self.signature(of: transcript, with: oldKey),
            sigNewKey: try Self.signature(of: transcript, with: newKey)
        )
    }

    /// Deletes the pending key; a no-op if there is none.
    public func deletePending() throws {
        try Self.ignoringNotFound { try keychainStore.deleteKey(tag: slots.inactiveTag()) }
    }

    /// Makes the key under `pendingTag` the identity: deletes the old identity certificate
    /// (regenerated for the new key on the next bootstrap), flips the active slot in one write,
    /// then deletes the old key. Idempotent and safe to re-run after a crash at any step.
    public func promote(pendingTag: String) throws {
        if try slots.activeTag() != pendingTag {
            try Self.ignoringNotFound { try keychainStore.deleteCertificate(label: identityCertLabel) }
            try slots.activate(pendingTag)
        }
        try deletePending()
    }

    private static func ignoringNotFound(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch KeychainError.itemNotFound {
            return
        }
    }

    private static func spkiDer(of key: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(key),
              let x963 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw KeychainError.unhandled(status: errSecParam)
        }
        return try P256.Signing.PublicKey(x963Representation: x963).derRepresentation
    }

    private static func signature(of message: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, signingAlgorithm, message as CFData, &error) else {
            throw KeychainError(error?.takeRetainedValue())
        }
        return signature as Data
    }
}
