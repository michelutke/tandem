import Foundation
import Synchronization
import TandemCrypto
import TandemProtocol
import TandemStore

/// A Mac-initiated rotation in flight (E70-03, D-34): which paired phones (by permanent record id)
/// still have to ack the new key, and whether the switch is already committed.
public struct RotationAttempt: Equatable, Sendable, Codable {
    public let startedAt: Date
    /// Keychain tag of the pending key; it becomes the active identity tag on commit.
    public let newKeyTag: String
    public var committed: Bool
    /// Record id (hex) of every phone paired since the rotation began, mapped to "has acked".
    public var acknowledged: [String: Bool]

    public var pendingRecordIds: [String] {
        acknowledged.filter { !$0.value }.map(\.key).sorted()
    }
}

public enum RotationCoordinatorError: Error, Equatable {
    case pairingWindowOpen
    case noActiveIdentity
    case noPairedPhones
    case notInProgress
    case alreadyCommitted
    case finishNotYetAvailable
}

/// Initiator side of key rotation for the Mac's own identity (E70-03, SPEC.md #key-rotation, D-34).
/// The new key is generated beside the active identity and the attempt (pending key plus per-phone
/// ack state) is one Keychain item, so a restart resumes exactly where it stopped. The active
/// identity switches only after every currently paired phone, including any paired mid-rotation,
/// has acked; `finish()` after 7 days unpairs the stragglers first, `cancel()` drops the pending key.
/// A valid old identity is never replaced by a freshly generated one.
public final class RotationCoordinator: Sendable {
    private static let attemptService = "com.tandem.rotation.attempt.v1"
    private static let attemptAccount = "attempt"

    private let keychainStore: any KeychainStore
    private let trustStore: TrustStore
    private let window: any PairingWindowState
    private let dateProvider: DateProvider
    private let onSwitched: @Sendable () -> Void
    private let lock = Mutex<Void>(())

    /// `onSwitched` runs after the identity key swap so the owner can re-bootstrap the identity and
    /// restart the listener on the new key.
    public init(
        keychainStore: any KeychainStore,
        trustStore: TrustStore,
        window: any PairingWindowState,
        dateProvider: @escaping DateProvider,
        onSwitched: @escaping @Sendable () -> Void = {}
    ) {
        self.keychainStore = keychainStore
        self.trustStore = trustStore
        self.window = window
        self.dateProvider = dateProvider
        self.onSwitched = onSwitched
    }

    public func attempt() throws -> RotationAttempt? {
        try lock.withLock { _ in try loadAttempt() }
    }

    /// Generates the pending key and persists the attempt. Returns the existing attempt, without a
    /// second key, if one is already in progress.
    @discardableResult
    public func begin() throws -> RotationAttempt {
        try lock.withLock { _ in
            if let existing = try loadAttempt() { return existing }
            guard !window.isOpen else { throw RotationCoordinatorError.pairingWindowOpen }
            let keys = RotationKeyProvider(keychainStore: keychainStore)
            do {
                _ = try keys.activeSpkiDer()
            } catch KeychainError.itemNotFound {
                throw RotationCoordinatorError.noActiveIdentity
            }
            let phones = try trustStore.list()
            guard !phones.isEmpty else { throw RotationCoordinatorError.noPairedPhones }
            _ = try keys.getOrCreatePendingSpkiDer()
            let attempt = RotationAttempt(
                startedAt: dateProvider(),
                newKeyTag: try keys.pendingTag(),
                committed: false,
                acknowledged: Dictionary(uniqueKeysWithValues: phones.map { ($0.recordId.hexString, false) })
            )
            try saveAttempt(attempt)
            return attempt
        }
    }

    /// The signed `KeyRotation` for the phone with `recordId`, or `nil` when there is nothing to
    /// send it: no attempt, switch committed, that phone already acked or not part of the attempt,
    /// or a pairing window is open.
    public func keyRotation(forRecordId recordId: SpkiFingerprint, challenge: Data) throws -> Tandem_V1_KeyRotation? {
        try lock.withLock { _ in
            guard !window.isOpen,
                  let attempt = try loadAttempt(), !attempt.committed,
                  attempt.acknowledged[recordId.hexString] == false else { return nil }
            let signed = try RotationKeyProvider(keychainStore: keychainStore).sign(challenge: challenge)
            var message = Tandem_V1_KeyRotation()
            message.newSpkiDer = signed.newSpkiDer
            message.sigOldKey = signed.sigOldKey
            message.sigNewKey = signed.sigNewKey
            return message
        }
    }

    /// Records the phone's `RotationAck`. Returns `true` if that completed the attempt and the
    /// identity switched.
    @discardableResult
    public func recordAck(forRecordId recordId: SpkiFingerprint) throws -> Bool {
        let switched = try lock.withLock { _ -> Bool in
            guard var attempt = try loadAttempt(), !attempt.committed,
                  attempt.acknowledged[recordId.hexString] != nil else { return false }
            attempt.acknowledged[recordId.hexString] = true
            try saveAttempt(attempt)
            return try switchIfComplete(attempt)
        }
        if switched { onSwitched() }
        return switched
    }

    /// Re-runs whatever a restart interrupted: a committed switch, or an attempt whose remaining
    /// phones were all unpaired meanwhile. Returns `true` if the identity switched.
    @discardableResult
    public func resume() throws -> Bool {
        let switched = try lock.withLock { _ -> Bool in
            guard let attempt = try loadAttempt() else { return false }
            return try switchIfComplete(attempt)
        }
        if switched { onSwitched() }
        return switched
    }

    /// Offered after 7 days with phones still pending: unpairs the pending phones, then switches.
    public func finish() throws {
        let switched = try lock.withLock { _ -> Bool in
            guard let attempt = try loadAttempt() else { throw RotationCoordinatorError.notInProgress }
            guard !attempt.committed else { return try switchIfComplete(attempt) }
            guard dateProvider() >= attempt.startedAt.addingTimeInterval(TrustStore.gracePinLifetime) else {
                throw RotationCoordinatorError.finishNotYetAvailable
            }
            try unpair(recordIds: Set(attempt.pendingRecordIds))
            return try switchIfComplete(attempt)
        }
        if switched { onSwitched() }
    }

    /// Deletes the pending key and the attempt; the old identity stays active. Not possible once
    /// the switch is committed.
    public func cancel() throws {
        try lock.withLock { _ in
            guard let attempt = try loadAttempt() else { throw RotationCoordinatorError.notInProgress }
            guard !attempt.committed else { throw RotationCoordinatorError.alreadyCommitted }
            try RotationKeyProvider(keychainStore: keychainStore).deletePending()
            try keychainStore.deleteGenericPassword(service: Self.attemptService, account: Self.attemptAccount)
        }
    }

    /// Commits and completes the switch when every phone of the attempt has acked or is no longer
    /// paired, or when it was already committed.
    private func switchIfComplete(_ attempt: RotationAttempt) throws -> Bool {
        var attempt = attempt
        if !attempt.committed {
            let paired = try trustStore.list().map(\.recordId.hexString)
            guard paired.allSatisfy({ attempt.acknowledged[$0] == true }) else { return false }
            attempt.committed = true
            try saveAttempt(attempt)
        }
        try RotationKeyProvider(keychainStore: keychainStore).promote(pendingTag: attempt.newKeyTag)
        try keychainStore.deleteGenericPassword(service: Self.attemptService, account: Self.attemptAccount)
        return true
    }

    private func unpair(recordIds: Set<String>) throws {
        for record in try trustStore.list() where recordIds.contains(record.recordId.hexString) {
            try trustStore.unpair(record.fingerprint)
        }
    }

    private func loadAttempt() throws -> RotationAttempt? {
        do {
            let data = try keychainStore.copyGenericPassword(service: Self.attemptService, account: Self.attemptAccount)
            var attempt = try JSONDecoder().decode(RotationAttempt.self, from: data)
            if !attempt.committed {
                for phone in try trustStore.list() where attempt.acknowledged[phone.recordId.hexString] == nil {
                    attempt.acknowledged[phone.recordId.hexString] = false
                }
            }
            return attempt
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    private func saveAttempt(_ attempt: RotationAttempt) throws {
        let data = try JSONEncoder().encode(attempt)
        do {
            try keychainStore.addGenericPassword(
                service: Self.attemptService,
                account: Self.attemptAccount,
                data: data,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        } catch KeychainError.duplicateItem {
            try keychainStore.updateGenericPassword(
                service: Self.attemptService,
                account: Self.attemptAccount,
                data: data
            )
        }
    }
}
