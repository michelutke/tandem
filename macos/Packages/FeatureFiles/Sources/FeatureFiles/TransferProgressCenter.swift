import Foundation
import Observation
import SwiftUI

/// Where ``FileSender`` and ``FileReceiver`` report one transfer's lifecycle (backlog E40-25).
/// `delivered` carries the cumulative byte count; `cancel` is the E40-20 flow
/// (`FileSender.cancel()` / `FileReceiver.cancel(id:)`).
public protocol TransferProgressReporting: Sendable {
    func began(id: String, name: String, totalBytes: Int64, cancel: @escaping @Sendable () async -> Void) async
    func delivered(id: String, bytes: Int64) async
    func ended(id: String) async
}

/// A transfer that is no longer in flight, kept for the main window's "Earlier" list.
public struct EarlierTransfer: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let totalBytes: Int64
    public let endedAt: Date?

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
/// active transfer, added on `began` and removed on `ended`.
@MainActor
@Observable
public final class TransferProgressCenter: TransferProgressReporting {
    public private(set) var rows: [TransferProgressViewModel] = []
    /// Transfers that ended without being cancelled, newest first; lives for the process only.
    public private(set) var earlier: [EarlierTransfer] = []

    private static let earlierLimit = 20

    private let clock: any Clock<Duration>
    private let now: (@Sendable () -> Date)?

    public nonisolated init(clock: any Clock<Duration>, now: (@Sendable () -> Date)? = nil) {
        self.clock = clock
        self.now = now
    }

    public func began(id: String, name: String, totalBytes: Int64, cancel: @escaping @Sendable () async -> Void) {
        rows.removeAll { $0.id == id }
        rows.append(TransferProgressViewModel(id: id, name: name, totalBytes: totalBytes, clock: clock, cancel: cancel))
    }

    public func delivered(id: String, bytes: Int64) {
        rows.first { $0.id == id }?.record(deliveredBytes: bytes)
    }

    public func ended(id: String) {
        if let row = rows.first(where: { $0.id == id }), !row.isCancelled {
            earlier.removeAll { $0.id == id }
            earlier.insert(
                EarlierTransfer(id: id, name: row.name, totalBytes: row.totalBytes, endedAt: now?()),
                at: 0
            )
            earlier = Array(earlier.prefix(Self.earlierLimit))
        }
        rows.removeAll { $0.id == id }
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
