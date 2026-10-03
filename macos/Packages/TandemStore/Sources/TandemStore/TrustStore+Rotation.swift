import Foundation
import Synchronization
import TandemCrypto

/// Which pin of a record authenticated a session (E70-05).
public enum AuthenticatedPin: Sendable, Equatable {
    case primary
    case grace
}

/// A peer record together with the pin that authenticated the current session.
public struct AuthenticatedPeer: Sendable, Equatable {
    public let record: PeerRecord
    public let pin: AuthenticatedPin
}

/// Rotation writes failing because the record changed under the caller.
public enum TrustStoreRotationError: Error, Equatable {
    case recordChanged
}

extension TrustStore {
    /// Serializes every read-modify-write of a peer record's rotation state in this process.
    private static let rotationWrites = Mutex<Void>(())

    /// How long the previous pin stays accepted after a rotation (SPEC.md #key-rotation "Grace pin").
    public static let gracePinLifetime: TimeInterval = 7 * 24 * 60 * 60

    /// The record `fingerprint` authenticates, as its primary pin or as an unexpired grace pin.
    /// Compares against every stored pin in constant time with no early exit (invariants 3, 6).
    public func authenticatedPeer(_ fingerprint: SpkiFingerprint, now: Date) throws -> AuthenticatedPeer? {
        var found: AuthenticatedPeer?
        for record in try list() {
            if record.fingerprint.matches(fingerprint) {
                found = AuthenticatedPeer(record: record, pin: .primary)
            }
            if let grace = record.gracePin, grace.expiresAt > now, grace.fingerprint.matches(fingerprint) {
                found = AuthenticatedPeer(record: record, pin: .grace)
            }
        }
        return found
    }

    /// Whether `fingerprint` equals any record's primary or grace pin, expired or not.
    public func holdsPin(_ fingerprint: SpkiFingerprint) throws -> Bool {
        var held = false
        for record in try list() {
            if record.fingerprint.matches(fingerprint) { held = true }
            if let grace = record.gracePin, grace.fingerprint.matches(fingerprint) { held = true }
        }
        return held
    }

    /// Pins `newFingerprint` as `record`'s primary and keeps the old primary as a grace pin
    /// expiring `gracePinLifetime` after `now`. One Keychain item update: the record is either
    /// entirely old or entirely new. Throws `recordChanged` if another rotation already replaced
    /// `record`'s primary.
    public func rotatePrimary(of record: PeerRecord, to newFingerprint: SpkiFingerprint, now: Date) throws {
        try Self.rotationWrites.withLock { _ in
            guard let current = try list().first(where: { $0.recordId == record.recordId }),
                current.fingerprint.matches(record.fingerprint)
            else { throw TrustStoreRotationError.recordChanged }
            var rotated = current
            rotated.gracePin = GracePin(
                fingerprint: record.fingerprint,
                expiresAt: now.addingTimeInterval(Self.gracePinLifetime)
            )
            rotated.fingerprint = newFingerprint
            try replace(rotated)
        }
    }

    /// Marks the unused grace pin `fingerprint` matches as used. `false` when none matches or it
    /// was already used: a grace pin authenticates at most one Ready session.
    public func claimGracePin(_ fingerprint: SpkiFingerprint) throws -> Bool {
        try Self.rotationWrites.withLock { _ in
            for var record in try list() {
                guard var grace = record.gracePin, !grace.used, grace.fingerprint.matches(fingerprint) else {
                    continue
                }
                grace.used = true
                record.gracePin = grace
                try replace(record)
                return true
            }
            return false
        }
    }

    /// Drops the grace pin of the record whose primary is `fingerprint`: a session authenticated
    /// with the new key completed `VersionHello`.
    public func purgeGracePin(authenticatedByPrimary fingerprint: SpkiFingerprint) throws {
        try Self.rotationWrites.withLock { _ in
            guard var record = try get(fingerprint), record.gracePin != nil else { return }
            record.gracePin = nil
            try replace(record)
        }
    }

    /// Drops the grace pin that `fingerprint` matches: the grace session closed.
    public func purgeGracePin(authenticatedByGrace fingerprint: SpkiFingerprint) throws {
        try Self.rotationWrites.withLock { _ in
            for var record in try list() {
                guard let grace = record.gracePin, grace.fingerprint.matches(fingerprint) else { continue }
                record.gracePin = nil
                try replace(record)
            }
        }
    }

    /// Drops every grace pin whose lifetime ended at or before `now`.
    public func purgeExpiredGracePins(now: Date) throws {
        try Self.rotationWrites.withLock { _ in
            for var record in try list() {
                guard let grace = record.gracePin, grace.expiresAt <= now else { continue }
                record.gracePin = nil
                try replace(record)
            }
        }
    }

    private func replace(_ record: PeerRecord) throws {
        try keychainStore.updateGenericPassword(
            service: Self.peerRecordService,
            account: record.recordId.hexString,
            data: try Self.encoder.encode(record)
        )
    }
}
