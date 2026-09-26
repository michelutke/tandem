import Foundation
import Observation
import TandemCrypto
import TandemStore

/// Wall-clock time seam, matching `TandemTestSupport.DateProvider`'s underlying closure type
/// structurally so tests can bridge a `ManualTestClock` in via `FixedDateProvider` without this
/// package depending on `TandemTestSupport` in its main target (E00-24 seam rule).
public typealias DateProvider = @Sendable () -> Date

/// The Mac main window's Devices screen (E14-14, `docs/design/ui-spec.md` §7.1 "Devices"): every
/// ``TrustStore`` (E13-06) record as a row with a relative last-seen and a per-row revoke button.
///
/// Presentation-independent -- no `SwiftUI`/`AppKit` import -- so it's unit-testable against a
/// real ``TrustStore`` (over `InMemoryKeychainStore`) and a fake `unpair` closure, the same way
/// ``PairConfirmationViewModel`` is tested against a real `PairingWindow`. ``PairedDevicesView`` is
/// its SwiftUI presentation.
///
/// `unpair` is injected as a plain closure rather than a concrete type: E14-13's `UnpairAction`
/// (local delete, then Revoke-if-connected) lands separately, so this view model only needs its
/// shape -- take the fingerprint to unpair, do the work, possibly throw.
@MainActor
@Observable
public final class PairedDevicesViewModel {
    /// One row: a sanitized display name (already sanitized on write into the trust store, e.g.
    /// by the pairing confirmation dialog, E14-08) and a formatted relative last-seen string.
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: SpkiFingerprint
        public let displayName: String
        public let lastSeenText: String
    }

    /// Every paired device, sorted by display name (case-insensitive, locale-aware).
    public private(set) var rows: [Row] = []

    /// The row a revoke confirmation is pending for, or `nil` if no confirmation is showing.
    public var pendingRevoke: Row?

    private let trustStore: TrustStore
    private let dateProvider: DateProvider
    private let unpair: @Sendable (SpkiFingerprint) async throws -> Void
    private let relativeDateFormatter: RelativeDateTimeFormatter

    public init(
        trustStore: TrustStore,
        dateProvider: @escaping DateProvider,
        unpair: @escaping @Sendable (SpkiFingerprint) async throws -> Void
    ) {
        self.trustStore = trustStore
        self.dateProvider = dateProvider
        self.unpair = unpair
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        self.relativeDateFormatter = formatter
        refresh()
    }

    /// Reloads ``rows`` from ``trustStore``, recomputing every last-seen string against
    /// `dateProvider()`'s current value. A `trustStore.list()` failure leaves ``rows`` empty
    /// rather than throwing, since this is called from view-lifecycle hooks that can't surface
    /// an error.
    public func refresh() {
        let now = dateProvider()
        let records = (try? trustStore.list()) ?? []
        rows = records
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map { record in
                Row(
                    id: record.fingerprint,
                    displayName: record.displayName,
                    lastSeenText: relativeDateFormatter.localizedString(for: record.lastSeen, relativeTo: now)
                )
            }
    }

    /// The owner tapped Revoke on `row`: shows the confirmation, does nothing else yet.
    public func requestRevoke(_ row: Row) {
        pendingRevoke = row
    }

    /// The owner dismissed the revoke confirmation without confirming.
    public func cancelRevoke() {
        pendingRevoke = nil
    }

    /// The owner confirmed the revoke: removes `pendingRevoke`'s row immediately (optimistic on
    /// local delete) and starts `unpair` in the background -- the row disappears before the
    /// Revoke send (which `unpair` may do) completes. A no-op if nothing is pending.
    public func confirmRevoke() {
        guard let row = pendingRevoke else { return }
        pendingRevoke = nil
        rows.removeAll { $0.id == row.id }
        let unpair = self.unpair
        Task {
            try? await unpair(row.id)
        }
    }
}
