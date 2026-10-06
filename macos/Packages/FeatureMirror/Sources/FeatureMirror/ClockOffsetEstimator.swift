/// One clock-sync round trip (E61-08): the Mac sends a probe at `sentMs` (Mac clock), the phone answers
/// with its own clock `phoneMs`, and the Mac receives that answer at `receivedMs` (Mac clock).
public struct ClockRoundTrip: Equatable, Sendable {
    public let sentMs: Int64
    public let phoneMs: Int64
    public let receivedMs: Int64

    public init(sentMs: Int64, phoneMs: Int64, receivedMs: Int64) {
        self.sentMs = sentMs
        self.phoneMs = phoneMs
        self.receivedMs = receivedMs
    }

    var rttMs: Int64 { receivedMs - sentMs }
}

/// Estimates the phone-minus-Mac clock offset from the minimum-RTT round trip, which bounds the error
/// by half that RTT (E61-08).
public enum ClockOffsetEstimator {
    public static func offsetMs(from roundTrips: [ClockRoundTrip]) -> Double? {
        guard let best = roundTrips.min(by: { $0.rttMs < $1.rttMs }) else { return nil }
        return Double(best.phoneMs) - Double(best.sentMs + best.receivedMs) / 2
    }
}
