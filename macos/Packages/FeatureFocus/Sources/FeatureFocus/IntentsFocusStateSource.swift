import Intents

/// Seam over `INFocusStatusCenter` so the polling and authorization logic is testable.
public protocol FocusStatusReading: Sendable {
    func requestAuthorization() async -> Bool
    func isFocused() -> Bool?
}

/// Production ``FocusStatusReading`` over `INFocusStatusCenter.default` (macOS 12+, E72-03).
public struct SystemFocusStatusReader: FocusStatusReading {
    public init() {}

    public func requestAuthorization() async -> Bool {
        let center = INFocusStatusCenter.default
        switch center.authorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default:
            return false
        }
    }

    public func isFocused() -> Bool? {
        INFocusStatusCenter.default.focusStatus.isFocused
    }
}

/// Production ``FocusStateSource`` (E72-03): `INFocusStatusCenter` has no change notification, so
/// the status is polled and yielded when it differs from the last value. Authorization is requested
/// on the first `changes` consumption; when it is not granted the stream finishes without yielding,
/// which the sender treats as "capability unavailable".
public struct IntentsFocusStateSource: FocusStateSource {
    private let reader: any FocusStatusReading
    private let pollInterval: Duration
    private let clock: any Clock<Duration>

    public init(
        reader: any FocusStatusReading = SystemFocusStatusReader(),
        pollInterval: Duration = .seconds(2),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.reader = reader
        self.pollInterval = pollInterval
        self.clock = clock
    }

    public var changes: AsyncStream<Bool> {
        let reader = reader
        let pollInterval = pollInterval
        let clock = clock
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                guard await reader.requestAuthorization() else {
                    continuation.finish()
                    return
                }
                var last: Bool?
                while !Task.isCancelled {
                    if let current = reader.isFocused(), current != last {
                        last = current
                        continuation.yield(current)
                    }
                    try? await clock.sleep(for: pollInterval)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
