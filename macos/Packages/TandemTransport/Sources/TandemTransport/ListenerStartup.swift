import Foundation
import Observation

/// Why the production listener did not start; each case has a one-line reason for the failed
/// state (ui-spec "Tandem can't start.").
public enum ListenerFailureReason: Equatable, Sendable {
    /// The keychain refused access to the Mac identity (prompt unanswered, denied or cancelled,
    /// or the keychain is locked).
    case keychainAccess
    /// The identity could not be read or created for another reason.
    case identityUnavailable
    /// The listener could not bind a network port.
    case portUnavailable
    case unknown

    public var message: String {
        switch self {
        case .keychainAccess: "Keychain access was not granted."
        case .identityUnavailable: "This Mac's identity is unavailable."
        case .portUnavailable: "The network port is unavailable."
        case .unknown: "Something went wrong while starting."
        }
    }

    /// Whole tokens that mark a keychain access failure: names of ``KeychainError`` cases and the
    /// exact OSStatus codes (auth failed, interaction not allowed, user canceled, missing
    /// entitlement, no access for item, not available, interaction required).
    private static let keychainAccessTokens: Set<String> = [
        "authFailed", "locked", "errSecAuthFailed", "errSecInteractionNotAllowed", "errSecUserCanceled",
        "-128", "-25293", "-25308", "-34018", "-25243", "-25291", "-25315"
    ]

    private static func isKeychainAccess(_ description: String) -> Bool {
        description
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "-") })
            .contains { keychainAccessTokens.contains(String($0)) }
    }

    /// Whether the app becoming active may retry on its own. Never for a keychain failure: the
    /// access prompt lives in another process, so denying it would reactivate Tandem and raise a
    /// new prompt in a loop. Those retry only from the explicit Retry button.
    public var retriesOnActivation: Bool {
        switch self {
        case .keychainAccess, .identityUnavailable: false
        case .portUnavailable, .unknown: true
        }
    }

    /// Classifies a keychain or identity error's description.
    public static func classify(identityError description: String) -> ListenerFailureReason {
        isKeychainAccess(description) ? .keychainAccess : .identityUnavailable
    }

    /// Classifies an error thrown while starting the listener.
    public static func classify(listenerError error: any Error) -> ListenerFailureReason {
        if error is ListenerBindError { return .portUnavailable }
        return isKeychainAccess(String(describing: error)) ? .keychainAccess : .unknown
    }
}

public struct ListenerStartFailure: Error, Equatable, Sendable {
    public let reason: ListenerFailureReason

    public init(_ reason: ListenerFailureReason) {
        self.reason = reason
    }
}

public extension ListenerStartFailure {
    /// The failure for an identity that is not ready; `nil` when it is.
    init?(identityState: IdentityState) {
        switch identityState {
        case .ready: return nil
        case .error(let description): self.init(.classify(identityError: description))
        case .missing: self.init(.identityUnavailable)
        }
    }
}

public extension ListenerController {
    /// ``start()`` with its failure mapped to a ``ListenerFailureReason``.
    func startResult() -> Result<StartedListener, ListenerStartFailure> {
        do {
            guard let listener = try start() else {
                return .failure(ListenerStartFailure(.identityUnavailable))
            }
            return .success(listener)
        } catch {
            return .failure(ListenerStartFailure(.classify(listenerError: error)))
        }
    }
}

/// Owns the one production listener start and its visible failure (invariant 5: closed must also
/// be visible). A failed start is retried only on an explicit ``retry()`` (the Retry button, or the
/// app becoming active while failed) -- never in a background loop.
@MainActor
@Observable
public final class ListenerStartupModel<Lifecycle> {
    public enum Phase: Equatable {
        case notStarted
        case started
        case failed(ListenerFailureReason)
    }

    public private(set) var phase: Phase = .notStarted
    /// Bumped on every successful start, so views built from the lifecycle can be rebuilt.
    public private(set) var generation = 0
    public private(set) var lifecycle: Lifecycle?

    @ObservationIgnored private let startAction: @MainActor () -> Result<Lifecycle, ListenerStartFailure>
    @ObservationIgnored private let onStarted: @MainActor (Lifecycle) -> Void
    @ObservationIgnored private var isStarting = false

    /// - Parameters:
    ///   - start: composes and starts the listener; called at most once at a time.
    ///   - onStarted: runs on success, before ``phase`` becomes `.started`.
    public init(
        start: @escaping @MainActor () -> Result<Lifecycle, ListenerStartFailure>,
        onStarted: @escaping @MainActor (Lifecycle) -> Void = { _ in }
    ) {
        startAction = start
        self.onStarted = onStarted
    }

    /// Starts the listener unless one is already running or a start is in flight.
    public func start() {
        guard !isStarting, lifecycle == nil else { return }
        isStarting = true
        defer { isStarting = false }
        switch startAction() {
        case .success(let started):
            lifecycle = started
            onStarted(started)
            generation += 1
            phase = .started
        case .failure(let failure):
            phase = .failed(failure.reason)
        }
    }

    /// The app became active: retries once, only for a failure that is safe to retry unprompted
    /// (see ``ListenerFailureReason/retriesOnActivation``).
    public func retryOnActivation() {
        guard case .failed(let reason) = phase, reason.retriesOnActivation else { return }
        start()
    }

    /// Runs ``start()`` again, only while in the failed state.
    public func retry() {
        guard case .failed = phase else { return }
        start()
    }
}
