import Foundation
import Observation

/// One progress emission: whole-number percent, trailing-window speed and the injected-clock
/// offset at which it was produced.
public struct TransferProgress: Equatable, Sendable {
    public let percent: Int
    public let bytesPerSecond: Double
    public let at: Duration
}

/// Drives one in-flight transfer row in the menu bar window (backlog E40-23, PRD F-7.1): percent,
/// speed averaged over the trailing 3 s, and Cancel. Emissions are throttled to at most one per
/// 250 ms so a fast link does not redraw per chunk. Time comes only from the injected clock.
@MainActor
@Observable
public final class TransferProgressViewModel {
    static let speedWindow: Duration = .seconds(3)
    static let minEmissionInterval: Duration = .milliseconds(250)

    public let id: String
    public let name: String
    public private(set) var progress: TransferProgress
    public private(set) var deliveredBytes: Int64 = 0
    public private(set) var isCancelled = false

    private let totalBytes: Int64
    private let elapsed: () -> Duration
    private let cancelFlow: () async -> Void
    private var samples: [(at: Duration, bytes: Int64)]

    /// - Parameter cancel: the E40-20 cancel flow (`FileSender.cancel()` / `FileReceiver.cancel(id:)`).
    public init(
        id: String,
        name: String,
        totalBytes: Int64,
        clock: any Clock<Duration>,
        cancel: @escaping () async -> Void
    ) {
        self.id = id
        self.name = name
        self.totalBytes = totalBytes
        self.elapsed = Self.makeElapsed(clock)
        self.cancelFlow = cancel
        self.progress = TransferProgress(percent: 0, bytesPerSecond: 0, at: .zero)
        self.samples = [(.zero, 0)]
    }

    public var percentText: String { "\(progress.percent)%" }

    public var speedText: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(progress.bytesPerSecond), countStyle: .binary))/s"
    }

    /// Records the cumulative delivered byte count; publishes a new ``progress`` at most every 250 ms.
    public func record(deliveredBytes bytes: Int64) {
        let now = elapsed()
        deliveredBytes = bytes
        samples.append((now, bytes))
        samples.removeAll { now - $0.at > Self.speedWindow }
        guard progress.at == .zero || now - progress.at >= Self.minEmissionInterval else { return }
        progress = TransferProgress(percent: percent(of: bytes), bytesPerSecond: speed(now: now), at: now)
    }

    public func cancel() async {
        isCancelled = true
        await cancelFlow()
    }

    private func percent(of bytes: Int64) -> Int {
        guard totalBytes > 0 else { return 0 }
        return Int(min(bytes, totalBytes) * 100 / totalBytes)
    }

    private func speed(now: Duration) -> Double {
        guard let oldest = samples.first, now > oldest.at else { return 0 }
        let seconds = Double((now - oldest.at).components.seconds)
            + Double((now - oldest.at).components.attoseconds) / 1e18
        return Double(deliveredBytes - oldest.bytes) / seconds
    }

    private static func makeElapsed<C: Clock<Duration>>(_ clock: C) -> () -> Duration {
        let origin = clock.now
        return { origin.duration(to: clock.now) }
    }
}
