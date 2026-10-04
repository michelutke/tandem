import Foundation
import Observation
import TandemStore

public enum MacKeyRotationResult: Equatable, Sendable {
    case success(newFingerprint: String)
    case failure(reason: String)
}

/// A Mac-initiated rotation still waiting on phones (E70-03, D-34): when it started and the
/// sanitized display names of the phones that have not acked the new key.
public struct PendingRotation: Equatable, Sendable {
    public let startedAt: Date
    public let phoneNames: [String]

    public init(startedAt: Date, phoneNames: [String]) {
        self.startedAt = startedAt
        self.phoneNames = phoneNames
    }
}

/// Seam over E70-03's `RotationInitiator`/`RotationCoordinator` so the Settings view model needs no
/// transport types.
public protocol MacKeyRotator: Sendable {
    func rotate() async -> MacKeyRotationResult
    func pendingRotation() -> PendingRotation?
    func finishRotation() async throws
    func cancelRotation() async throws
}

public enum MacRotationState: Equatable, Sendable {
    case idle
    case confirming
    case inProgress
    case success(newFingerprint: String)
    case failed(reason: String)
}

/// The Mac Settings "Rotate key" action (E70-11, mirrors Android E70-06): idle -> confirming ->
/// in progress -> success / failed. Cancelling never calls the rotator, and a failure leaves
/// ``currentFingerprint`` untouched.
@MainActor
@Observable
public final class MacRotationSettingsViewModel {
    public static let disabledReasonText = "Connect your phone to rotate the key"
    public static let finishWarningText = "Pending phones will need to pair again"

    public private(set) var state: MacRotationState = .idle
    public private(set) var currentFingerprint: String
    public private(set) var pending: PendingRotation?
    public var hasAuthenticatedSession: Bool

    private let rotator: any MacKeyRotator
    private let dateProvider: DateProvider

    public init(
        rotator: any MacKeyRotator,
        currentFingerprint: String,
        hasAuthenticatedSession: Bool,
        dateProvider: @escaping DateProvider
    ) {
        self.rotator = rotator
        self.currentFingerprint = currentFingerprint
        self.hasAuthenticatedSession = hasAuthenticatedSession
        self.dateProvider = dateProvider
    }

    public var actionEnabled: Bool {
        hasAuthenticatedSession && state != .inProgress
    }

    public var disabledReason: String? {
        hasAuthenticatedSession ? nil : Self.disabledReasonText
    }

    public var pendingPhoneNames: [String] {
        pending?.phoneNames ?? []
    }

    public var pendingText: String? {
        guard let pending else { return nil }
        let count = pending.phoneNames.count
        return "Waiting for \(count) \(count == 1 ? "phone" : "phones") to confirm the new key"
    }

    public var canFinishPending: Bool {
        guard let pending else { return false }
        return dateProvider() >= pending.startedAt.addingTimeInterval(TrustStore.gracePinLifetime)
    }

    public var finishWarning: String? {
        canFinishPending ? Self.finishWarningText : nil
    }

    public func requestRotation() {
        if actionEnabled, state != .confirming { state = .confirming }
    }

    public func cancel() {
        if state == .confirming { state = .idle }
    }

    public func confirm() async {
        guard state == .confirming else { return }
        state = .inProgress
        switch await rotator.rotate() {
        case .success(let newFingerprint):
            currentFingerprint = newFingerprint
            state = .success(newFingerprint: newFingerprint)
        case .failure(let reason):
            state = .failed(reason: reason)
        }
        refreshPending()
    }

    public func dismissResult() {
        switch state {
        case .success, .failed: state = .idle
        default: break
        }
    }

    public func refreshPending() {
        pending = rotator.pendingRotation()
    }

    public func finishPending() async {
        guard canFinishPending else { return }
        try? await rotator.finishRotation()
        refreshPending()
    }

    public func cancelPending() async {
        try? await rotator.cancelRotation()
        refreshPending()
    }
}
