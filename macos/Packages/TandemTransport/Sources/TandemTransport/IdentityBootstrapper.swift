import Foundation
import Synchronization
import TandemCrypto

/// Identity lifecycle bootstrap (E10-09): mirrors Android's `IdentityBootstrapper` (E10-04). On
/// every access, verifies the Keychain identity key is usable with a real sign+verify smoke test
/// (`IdentityKeyProvider.hasUsableIdentityKey()`), not just presence of the item -- the Keychain
/// can retain an item whose key material is no longer usable. If the key item is missing or fails
/// the smoke test, the key and certificate are deleted and regenerated via `SecIdentityProvider`
/// (which chains through `IdentityCertProvider` and `IdentityKeyProvider`). The smoke test itself
/// stays inside `TandemCrypto`: the `key_material_only_in_crypto` lint rule (E10-14) forbids this
/// module from referencing `SecKey*` directly.
///
/// SPEC.md: regenerating the identity changes the Mac's SPKI fingerprint (invariant 3), so every
/// phone that previously paired against the old key no longer recognizes this Mac. `requiresRePair`
/// surfaces that (invariant 5) until `notifyPairingSucceeded()` is called after the next successful
/// pairing.
///
/// A Keychain failure that is neither "missing" nor a smoke-test failure -- `errSecAuthFailed` or
/// `errSecInteractionNotAllowed` (device locked) -- is surfaced as `IdentityState.error` directly:
/// never treated as "missing" (no delete-and-regenerate), never retried, and never backed by an
/// in-memory fallback key (UC-01 alternate flow).
///
/// Reaches the Keychain only through `any KeychainStore` (E10-16): unit tests exercising the
/// injected-failure paths use `InMemoryKeychainStore` (`TandemTestSupport`); paths that need a real
/// `SecIdentity` -- nothing can fake one, spike E03-02 -- use the throwaway on-disk file keychain
/// (`TemporaryKeychain`, D-75).
public final class IdentityBootstrapper: IdentityStateProvider, Sendable {

    private struct State {
        var identityState: IdentityState = .missing
        var requiresRePair = false
    }

    private let keychainStore: any KeychainStore
    private let onIdentityReset: @Sendable () -> Void
    private let smokeTest: IdentityKeyProvider.SmokeTest?
    private let state = Mutex(State())

    /// - Parameter smokeTest: replaces the real sign+verify probe in tests.
    public init(
        keychainStore: any KeychainStore,
        onIdentityReset: @escaping @Sendable () -> Void = {},
        smokeTest: IdentityKeyProvider.SmokeTest? = nil
    ) {
        self.keychainStore = keychainStore
        self.onIdentityReset = onIdentityReset
        self.smokeTest = smokeTest
    }

    /// The most recently computed identity state -- `.missing` until `bootstrapIdentity()` is
    /// called at least once. `ListenerController` (E12-01) reads this without triggering another
    /// Keychain round trip on every listener start.
    public var identityState: IdentityState {
        state.withLock { $0.identityState }
    }

    /// True from an identity reset until `notifyPairingSucceeded()` is called (SPEC.md,
    /// invariant 5).
    public var requiresRePair: Bool {
        state.withLock { $0.requiresRePair }
    }

    /// Returns the Mac's current identity state, reusing an existing usable identity or
    /// generating/regenerating one as needed. Safe to call on every launch and every access.
    @discardableResult
    public func bootstrapIdentity() -> IdentityState {
        let newState = computeIdentityState()
        state.withLock { $0.identityState = newState }
        return newState
    }

    /// Call once a pairing completes successfully; clears `requiresRePair` until the next reset.
    public func notifyPairingSucceeded() {
        state.withLock { $0.requiresRePair = false }
    }

    private func computeIdentityState() -> IdentityState {
        do {
            let usable = try IdentityKeyProvider(keychainStore: keychainStore, smokeTest: smokeTest)
                .hasUsableIdentityKey()
            let adoptingPendingKey = usable
                && RotationCoordinator.isAdoptingUnackedPendingKey(keychainStore: keychainStore)
            return usable && !adoptingPendingKey ? try readyState() : resetIdentity()
        } catch let error as KeychainError {
            return .error(String(describing: error))
        } catch {
            return .error(String(describing: error))
        }
    }

    /// Deletes the existing key and certificate (best-effort -- either may already be absent) and
    /// regenerates both. When a key or certificate existed, surfaces `requiresRePair` and
    /// `onIdentityReset` regardless of whether regeneration itself succeeds; a first-ever
    /// generation surfaces neither.
    private func resetIdentity() -> IdentityState {
        let hadIdentity = identityMaterialExists()
        try? keychainStore.deleteCertificate(label: identityCertLabel)
        try? keychainStore.deleteGenericPassword(
            service: RotationCoordinator.attemptService, account: RotationCoordinator.attemptAccount
        )
        for tag in [identityKeyApplicationTag, IdentityKeySlots.secondaryTag] {
            try? keychainStore.deleteKey(tag: tag)
        }
        if hadIdentity {
            state.withLock { $0.requiresRePair = true }
            onIdentityReset()
        }
        do {
            return try readyState()
        } catch {
            return .error(String(describing: error))
        }
    }

    /// Whether a key or certificate already existed: only then does regenerating change the SPKI a
    /// phone pinned. A first-ever generation is not a reset.
    private func identityMaterialExists() -> Bool {
        let keyExists = [identityKeyApplicationTag, IdentityKeySlots.secondaryTag].contains {
            (try? keychainStore.copyKey(tag: $0)) != nil
        }
        return keyExists
            || (try? keychainStore.copyCertificate(label: identityCertLabel)) != nil
            || (try? keychainStore.copyGenericPassword(service: Self.lineageService, account: Self.lineageAccount))
                != nil
    }

    /// Remembers that this Mac once had an identity, so losing the key item later still counts as
    /// a reset (a phone pinned the old SPKI) rather than a first generation.
    private func recordIdentityLineage() {
        try? keychainStore.addGenericPassword(
            service: Self.lineageService,
            account: Self.lineageAccount,
            data: Data([1]),
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    private static let lineageService = "com.tandem.identity.lineage"
    private static let lineageAccount = "generated"

    private func readyState() throws -> IdentityState {
        let identity = try SecIdentityProvider(keychainStore: keychainStore).getOrCreateSecIdentity()
        recordIdentityLineage()
        return .ready(identity)
    }
}
