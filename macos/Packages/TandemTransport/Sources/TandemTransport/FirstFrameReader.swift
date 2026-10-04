import Foundation
import TandemProtocol

enum FirstFrameReadOutcome: Sendable {
    /// One complete frame; `wire` is its length prefix plus `body`.
    case frame(body: Data, wire: Data)
    case timedOut
    case rejected(CloseCode)
    /// The connection ended before a frame completed at a frame boundary, or the read failed.
    case ended
}

/// Reads exactly one length-prefixed frame (SPEC.md §3) off a fresh connection within the §10
/// first-frame deadline, measured on the injected clock. Never reads past that frame.
enum FirstFrameReader {
    static let deadline: Duration = .seconds(5)
    static let maxBodyBytes = 1_048_576

    /// `onDeadline` runs when the deadline wins, to tear the connection down so the pending read ends.
    static func read(
        from source: ByteStreamConnectionFrameSource,
        clock: any Clock<Duration>,
        onDeadline: @escaping @Sendable () -> Void
    ) async -> FirstFrameReadOutcome {
        await withTaskGroup(of: FirstFrameReadOutcome?.self) { group in
            group.addTask { await readFrame(from: source) }
            group.addTask {
                guard (try? await clock.sleep(for: deadline)) != nil else { return nil }
                onDeadline()
                return .timedOut
            }
            var outcome = FirstFrameReadOutcome.ended
            if let first = await group.next(), let value = first {
                outcome = value
            }
            group.cancelAll()
            return outcome
        }
    }

    private static func readFrame(from source: ByteStreamConnectionFrameSource) async -> FirstFrameReadOutcome {
        do {
            let prefix = try await source.read(exactly: 4)
            guard prefix.count == 4 else { return prefix.isEmpty ? .ended : .rejected(.malformedFrame) }
            let length = prefix.reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= maxBodyBytes else { return .rejected(.malformedFrame) }
            let body = try await source.read(exactly: length)
            guard body.count == length else { return .rejected(.malformedFrame) }
            return .frame(body: body, wire: prefix + body)
        } catch {
            return .ended
        }
    }
}
