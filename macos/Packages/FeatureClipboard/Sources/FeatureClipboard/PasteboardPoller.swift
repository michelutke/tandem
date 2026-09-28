import AppKit

/// Polls ``PasteboardSource/changeCount`` every ``pollInterval`` on a background timer driven by
/// an injected `any Clock<Duration>` (E00-24 seam rule; `TandemTestSupport`'s `ManualTestClock` in
/// tests) rather than a real wall-clock sleep. On a detected change, reads
/// ``PasteboardSource/types()`` for the current item and reports them via `onChange`.
///
/// Each tick compares `changeCount` only against the value last seen at the *previous* tick, never
/// against an intermediate value observed some other way -- so two (or more) changes that land
/// within a single poll interval collapse into exactly one detection, of the latest item, on the
/// next tick.
public actor PasteboardPoller {
    /// E31-02: the polling interval.
    public static let pollInterval: Duration = .milliseconds(250)

    private let source: any PasteboardSource
    private let clock: any Clock<Duration>
    private let onChange: @Sendable ([NSPasteboard.PasteboardType]) async -> Void

    private var lastSeenChangeCount: Int
    private var pollTask: Task<Void, Never>?
    private var stopped = true

    public init(
        source: any PasteboardSource,
        clock: any Clock<Duration>,
        onChange: @escaping @Sendable ([NSPasteboard.PasteboardType]) async -> Void
    ) {
        self.source = source
        self.clock = clock
        self.onChange = onChange
        lastSeenChangeCount = source.changeCount
    }

    /// Starts the poll loop. A second call replaces the prior one, so this is safe to call more
    /// than once (matches `TandemTransport`'s `HeartbeatController`/`SleepWakeController`
    /// convention).
    public func start() {
        stopped = false
        pollTask?.cancel()
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    /// Stops the poll loop. Safe to call more than once, or without a prior ``start()``.
    public func stop() {
        stopped = true
        pollTask?.cancel()
    }

    deinit {
        pollTask?.cancel()
    }

    private func pollLoop() async {
        while !stopped {
            try? await clock.sleep(for: PasteboardPoller.pollInterval)
            guard !stopped, !Task.isCancelled else { return }
            await tick()
        }
    }

    private func tick() async {
        let currentChangeCount = source.changeCount
        guard currentChangeCount != lastSeenChangeCount else { return }
        lastSeenChangeCount = currentChangeCount
        await onChange(source.types())
    }
}
