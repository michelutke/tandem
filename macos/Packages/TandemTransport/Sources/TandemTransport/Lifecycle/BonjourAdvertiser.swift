import Foundation
import Network
import TandemCrypto

/// Wall-clock time seam for injecting now (E00-24) -- declared locally, structurally identical to
/// `TandemStore.PeerRecordUpdater`'s and `TandemDevices.PairedDevicesViewModel`'s own
/// `DateProvider` typealiases, rather than depending on `TandemTestSupport`'s copy: this package's
/// main target must not depend on `TandemTestSupport` (a test-support module, test-target
/// dependency only), but a test can still bridge in `TandemTestSupport.FixedDateProvider.provider`
/// since the closure shape is identical.
public typealias DateProvider = @Sendable () -> Date

/// Advertises this Mac's `_tandem._tcp` Bonjour service with a rotating instance name/TXT `id`
/// (E21-02, SPEC.md "Discovery TXT record"): the instance name and TXT `id` change once per UTC
/// calendar day, computed via ``DiscoveryRotatingId`` from an injected ``DateProvider`` (the wall
/// clock is never read directly, E00-24) -- so the id is stable across a machine's local time zone.
///
/// The day-boundary reschedule loop uses an injected `Clock<Duration>` (the task is never suspended
/// via an unseamed sleep call), following ``SleepWakeController``'s `observationTask`/`deinit {
/// task?.cancel() }` idiom for its own scheduled `Task` handle.
///
/// Composing this with `SystemPowerEvents`/`didWake` (so a sleeping Mac's clock jump is picked up
/// promptly) is a future issue's concern -- this type only exposes ``refreshForCurrentDay()`` for
/// that composition to call; it does not observe power events itself.
public actor BonjourAdvertiser {
    private static let secondsPerDay: Int64 = 86_400

    private let publisher: any BonjourPublisher
    private let macSpkiFingerprint: Data
    private let port: UInt16
    private let dateProvider: DateProvider
    private let clock: any Clock<Duration>
    private var refreshTask: Task<Void, Never>?
    /// Guards against a `stop()` that races an in-flight `refreshForCurrentDay()`: without this,
    /// `refreshForCurrentDay()` resuming after `await publishCurrentId()` would unconditionally
    /// call `scheduleNextRefresh()` even though `stop()` already ran, re-arming a timer nothing
    /// ever cancels and republishing at every midnight after the advertiser was told to stop.
    private var isRunning = false

    public init(
        publisher: any BonjourPublisher,
        macSpkiFingerprint: Data,
        port: UInt16,
        dateProvider: @escaping DateProvider,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.publisher = publisher
        self.macSpkiFingerprint = macSpkiFingerprint
        self.port = port
        self.dateProvider = dateProvider
        self.clock = clock
    }

    /// Publishes today's id, then schedules the day-boundary loop.
    public func start() async {
        isRunning = true
        await refreshForCurrentDay()
    }

    /// Recomputes the id for `dateProvider()`'s current instant and republishes, then reschedules
    /// the day-boundary loop off the new "now". Intended to be called by whatever composes this
    /// with `SystemPowerEvents`/`didWake` in a future issue.
    public func refreshForCurrentDay() async {
        refreshTask?.cancel()
        await publishCurrentId()
        // `stop()` may have run while `publishCurrentId()` was suspended above -- re-check
        // `isRunning` before arming a new timer, or a stopped advertiser would keep republishing
        // at every subsequent UTC midnight forever.
        guard isRunning else { return }
        scheduleNextRefresh()
    }

    /// Cancels the scheduled day-boundary loop and unpublishes. ``BonjourPublisher`` has no
    /// listener-affecting method at all by design: nothing this actor ever does -- including this
    /// call -- can cancel an open control connection.
    public func stop() async {
        isRunning = false
        refreshTask?.cancel()
        refreshTask = nil
        await publisher.unpublish()
    }

    deinit {
        refreshTask?.cancel()
    }

    private func publishCurrentId() async {
        let idHex = DiscoveryRotatingId.computeHex(
            macSpkiFingerprint: macSpkiFingerprint, dayIndex: currentDayIndex()
        )
        let txtRecord = NWTXTRecord(["v": "1", "id": idHex]).data
        await publisher.publish(instanceName: idHex, port: port, txtRecord: txtRecord)
    }

    private func scheduleNextRefresh() {
        // Two concurrent refreshForCurrentDay() calls (e.g. the wake hook racing the midnight
        // timer) would otherwise each schedule their own timer, overwriting refreshTask without
        // cancelling the previous one -- cancel explicitly first so exactly one survives.
        refreshTask?.cancel()

        let dayIndex = currentDayIndex()
        let nextMidnightUnixSecondsUtc = (dayIndex + 1) * Self.secondsPerDay
        let secondsUntilNextMidnight = nextMidnightUnixSecondsUtc - currentUnixSecondsUtc()

        let clock = self.clock
        refreshTask = Task { [weak self] in
            try? await clock.sleep(for: .seconds(secondsUntilNextMidnight))
            guard !Task.isCancelled else { return }
            await self?.refreshForCurrentDay()
        }
    }

    private func currentDayIndex() -> Int64 {
        DiscoveryRotatingId.dayIndex(unixSecondsUtc: currentUnixSecondsUtc())
    }

    private func currentUnixSecondsUtc() -> Int64 {
        Int64(dateProvider().timeIntervalSince1970)
    }
}
