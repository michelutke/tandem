import Foundation

/// Which way a file moved.
public enum TransferDirection: String, Sendable, Equatable {
    case phoneToMac = "phone_to_mac"
    case macToPhone = "mac_to_phone"
}

/// How a finished transfer ended; `failed` carries a reason code (never a file name).
public enum TransferOutcome: Sendable, Equatable {
    case completed
    case failed(reason: String)
    case cancelled

    var storageName: String {
        switch self {
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
    }

    var storageReason: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }

    init?(storageName: String, reason: String?) {
        switch storageName {
        case "completed": self = .completed
        case "failed": self = .failed(reason: reason ?? "")
        case "cancelled": self = .cancelled
        default: return nil
        }
    }
}

/// One finished transfer for the main window's "Earlier" list. `name` is the sanitized display
/// name and `savedFileBookmark` a bookmark of a received file; both stay local (invariant 7).
public struct TransferRecord: Equatable, Sendable, Identifiable {
    public let id: String
    public let direction: TransferDirection
    public let name: String
    public let sizeBytes: Int64
    public let finishedAtMs: Int64
    public let outcome: TransferOutcome
    public let savedFileBookmark: Data?

    public init(
        id: String,
        direction: TransferDirection,
        name: String,
        sizeBytes: Int64,
        finishedAtMs: Int64,
        outcome: TransferOutcome,
        savedFileBookmark: Data? = nil
    ) {
        self.id = id
        self.direction = direction
        self.name = name
        self.sizeBytes = sizeBytes
        self.finishedAtMs = finishedAtMs
        self.outcome = outcome
        self.savedFileBookmark = savedFileBookmark
    }
}

/// Persistent history of finished transfers, newest first, capped at ``maxRecords``.
public protocol TransferHistoryStore: Sendable {
    static var maxRecords: Int { get }

    /// Inserts (replacing the same id) and prunes the oldest beyond ``maxRecords``.
    func append(_ record: TransferRecord) async throws

    /// Newest first.
    func list() async throws -> [TransferRecord]

    func clear() async throws
}

public extension TransferHistoryStore {
    static var maxRecords: Int { 200 }
}

/// Array-backed ``TransferHistoryStore`` for view-model tests.
public actor InMemoryTransferHistoryStore: TransferHistoryStore {
    private var records: [TransferRecord] = []

    public init(records: [TransferRecord] = []) {
        self.records = records
    }

    public func append(_ record: TransferRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        records = Array(records.prefix(Self.maxRecords))
    }

    public func list() -> [TransferRecord] {
        records
    }

    public func clear() {
        records = []
    }
}
