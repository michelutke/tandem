import Foundation
import Observation
import SwiftUI
import TandemProtocol
import TandemStore

/// Where ``FileSender`` and ``FileReceiver`` report one transfer's lifecycle (backlog E40-25).
/// `delivered` carries the cumulative byte count; `cancel` is the E40-20 flow
/// (`FileSender.cancel()` / `FileReceiver.cancel(id:)`). `ended` carries how it ended and, for a
/// received file, where it was saved.
public protocol TransferProgressReporting: Sendable {
    func began(
        id: String,
        name: String,
        totalBytes: Int64,
        direction: TransferDirection,
        cancel: @escaping @Sendable () async -> Void
    ) async
    func delivered(id: String, bytes: Int64) async
    func ended(id: String, outcome: TransferOutcome, savedFile: URL?) async
}

public extension TransferProgressReporting {
    func ended(id: String, outcome: TransferOutcome) async {
        await ended(id: id, outcome: outcome, savedFile: nil)
    }
}

extension TransferOutcome {
    /// A peer or local abort: the user's own cancel is `cancelled`, anything else `failed` with
    /// the reason code.
    init(reason: Tandem_V1_TransferReason) {
        self = reason == .userCancelled ? .cancelled : .failed(reason: String(describing: reason))
    }
}

/// A transfer that is no longer in flight, kept for the main window's "Earlier" list.
public struct EarlierTransfer: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let totalBytes: Int64
    public let endedAt: Date?
    public let direction: TransferDirection
    public let outcome: TransferOutcome
    let savedFileBookmark: Data?

    init(
        id: String,
        name: String,
        totalBytes: Int64,
        endedAt: Date?,
        direction: TransferDirection,
        outcome: TransferOutcome,
        savedFileBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.totalBytes = totalBytes
        self.endedAt = endedAt
        self.direction = direction
        self.outcome = outcome
        self.savedFileBookmark = savedFileBookmark
    }

    init(record: TransferRecord) {
        self.init(
            id: record.id,
            name: record.name,
            totalBytes: record.sizeBytes,
            endedAt: Date(timeIntervalSince1970: Double(record.finishedAtMs) / 1000),
            direction: record.direction,
            outcome: record.outcome,
            savedFileBookmark: record.savedFileBookmark
        )
    }

    var record: TransferRecord {
        TransferRecord(
            id: id,
            direction: direction,
            name: name,
            sizeBytes: totalBytes,
            finishedAtMs: Int64(((endedAt ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970 * 1000).rounded()),
            outcome: outcome,
            savedFileBookmark: savedFileBookmark
        )
    }

    /// "To Mac" / "To phone".
    public var directionText: String {
        direction == .phoneToMac ? "To Mac" : "To phone"
    }

    /// Empty for a completed transfer.
    public var stateText: String {
        switch outcome {
        case .completed: ""
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    /// The received file, when it was saved and still exists.
    public var savedFileURL: URL? {
        guard outcome == .completed, direction == .phoneToMac, let savedFileBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: savedFileBookmark, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: totalBytes)
    }

    /// "14:02" for today, "Yesterday", otherwise "7 Oct"; empty without a clock.
    public func timeText(calendar: Calendar = .current) -> String {
        guard let endedAt else { return "" }
        if calendar.isDateInToday(endedAt) { return Self.format(endedAt, "HH:mm", calendar) }
        if calendar.isDateInYesterday(endedAt) { return "Yesterday" }
        return Self.format(endedAt, "d MMM", calendar)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// The in-flight transfer rows shown in the menu bar window: one ``TransferProgressViewModel`` per
/// active transfer, added on `began` and removed on `ended`. Finished transfers go to the
/// persistent ``TransferHistoryStore`` and the "Earlier" list loaded from it.
@MainActor
@Observable
public final class TransferProgressCenter: TransferProgressReporting {
    public private(set) var rows: [TransferProgressViewModel] = []
    /// Finished transfers (completed, failed or cancelled), newest first.
    public private(set) var earlier: [EarlierTransfer] = []

    private let clock: any Clock<Duration>
    private let now: (@Sendable () -> Date)?
    private let history: (any TransferHistoryStore)?
    @ObservationIgnored private var directions: [String: TransferDirection] = [:]

    public nonisolated init(
        clock: any Clock<Duration>,
        now: (@Sendable () -> Date)? = nil,
        history: (any TransferHistoryStore)? = nil
    ) {
        self.clock = clock
        self.now = now
        self.history = history
    }

    /// Loads the persisted "Earlier" list (call once at launch).
    public func loadEarlier() async {
        guard let records = try? await history?.list() else { return }
        let loaded = records.map(EarlierTransfer.init(record:))
        let loadedIds = Set(loaded.map(\.id))
        earlier = loaded + earlier.filter { !loadedIds.contains($0.id) }
    }

    /// Empties the "Earlier" list and the store.
    public func clearEarlier() async {
        earlier = []
        try? await history?.clear()
    }

    public func began(
        id: String,
        name: String,
        totalBytes: Int64,
        direction: TransferDirection,
        cancel: @escaping @Sendable () async -> Void
    ) {
        rows.removeAll { $0.id == id }
        directions[id] = direction
        rows.append(TransferProgressViewModel(id: id, name: name, totalBytes: totalBytes, clock: clock, cancel: cancel))
    }

    public func delivered(id: String, bytes: Int64) {
        rows.first { $0.id == id }?.record(deliveredBytes: bytes)
    }

    public func ended(id: String, outcome: TransferOutcome, savedFile: URL?) async {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        rows.removeAll { $0.id == id }
        let transfer = EarlierTransfer(
            id: id,
            name: row.name,
            totalBytes: row.totalBytes,
            endedAt: now?(),
            direction: directions.removeValue(forKey: id) ?? .phoneToMac,
            outcome: outcome,
            savedFileBookmark: savedFile.flatMap { try? $0.bookmarkData() }
        )
        earlier.removeAll { $0.id == id }
        earlier.insert(transfer, at: 0)
        earlier = Array(earlier.prefix(InMemoryTransferHistoryStore.maxRecords))
        try? await history?.append(transfer.record)
    }
}

/// The menu bar window's list of in-flight transfers; empty when nothing is transferring.
public struct TransferProgressListView: View {
    let center: TransferProgressCenter

    public init(center: TransferProgressCenter) {
        self.center = center
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(center.rows, id: \.id) { row in
                TransferProgressRow(viewModel: row)
            }
        }
    }
}
