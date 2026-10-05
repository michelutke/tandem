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

/// The in-flight transfer rows shown in the menu bar window: one ``TransferProgressViewModel`` per
/// active transfer, added on `began` and removed on `ended`.
@MainActor
@Observable
public final class TransferProgressCenter: TransferProgressReporting {
    public private(set) var rows: [TransferProgressViewModel] = []

    private let clock: any Clock<Duration>

    public nonisolated init(clock: any Clock<Duration>) {
        self.clock = clock
    }

    public func began(id: String, name: String, totalBytes: Int64, cancel: @escaping @Sendable () async -> Void) {
        rows.removeAll { $0.id == id }
        rows.append(TransferProgressViewModel(id: id, name: name, totalBytes: totalBytes, clock: clock, cancel: cancel))
    }

    public func delivered(id: String, bytes: Int64) {
        rows.first { $0.id == id }?.record(deliveredBytes: bytes)
    }

    public func ended(id: String) {
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
