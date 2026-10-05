import Foundation

/// A decoded frame as seen by the Mac: its overlay clock (phone clock) and the Mac receive time (E61-08).
public struct FrameSample: Equatable, Sendable {
    public let phoneClockMs: Int64
    public let receivedMs: Int64

    public init(phoneClockMs: Int64, receivedMs: Int64) {
        self.phoneClockMs = phoneClockMs
        self.receivedMs = receivedMs
    }
}

/// Sustained fps and p95 end-to-end latency over a run (E61-08, PRD success metric: 1080p >= 30 fps,
/// latency under 120 ms).
public struct LatencyReport: Equatable, Sendable {
    public let sustainedFps: Double
    public let p95LatencyMs: Double

    /// `phoneMinusMacOffsetMs` comes from ``ClockOffsetEstimator``. fps is frame intervals over the
    /// first-to-last receive span; p95 is nearest-rank. Nil with fewer than two samples or a zero span.
    public init?(samples: [FrameSample], phoneMinusMacOffsetMs: Double) {
        let received = samples.map(\.receivedMs)
        guard samples.count >= 2, let first = received.min(), let last = received.max(), last > first else {
            return nil
        }
        sustainedFps = Double(samples.count - 1) * 1000 / Double(last - first)
        let latencies = samples
            .map { Double($0.receivedMs) - (Double($0.phoneClockMs) - phoneMinusMacOffsetMs) }
            .sorted()
        p95LatencyMs = latencies[Int((0.95 * Double(latencies.count)).rounded(.up)) - 1]
    }
}
