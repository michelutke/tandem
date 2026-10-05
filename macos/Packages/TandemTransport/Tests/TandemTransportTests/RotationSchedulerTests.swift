import Foundation
import Synchronization
import Testing
import TandemTestSupport
@testable import TandemTransport

@Suite("RotationScheduler")
struct RotationSchedulerTests {
    static let interval = Duration.seconds(30 * 86_400)
    static let day: Duration = .seconds(86_400)

    final class MemoryStore: NextRotationDueStore {
        private let value: Mutex<Date?>
        init(_ due: Date? = nil) { value = Mutex(due) }
        func get() -> Date? { value.withLock { $0 } }
        func set(_ due: Date) { value.withLock { $0 = due } }
    }

    final class Counter: Sendable {
        private let count = Mutex(0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    struct Fixture {
        let clock = ManualTestClock()
        let counter = Counter()
        let store: MemoryStore
        let authenticated: AsyncStream<Bool>.Continuation
        let stream: AsyncStream<Bool>
        let scheduler: RotationScheduler
        let dates: FixedDateProvider

        init(store: MemoryStore = MemoryStore(), outcome: RotationOutcome = .committed) {
            self.store = store
            dates = FixedDateProvider(clock: clock)
            let (stream, continuation) = AsyncStream<Bool>.makeStream()
            self.stream = stream
            authenticated = continuation
            let counter = counter
            scheduler = RotationScheduler(
                clock: clock,
                dateProvider: dates.provider,
                interval: RotationSchedulerTests.interval,
                store: store,
                rotate: { counter.increment(); return outcome }
            )
        }

        func start() -> Task<Void, Never> {
            let scheduler = scheduler
            let stream = stream
            return Task { await scheduler.run(authenticated: stream) }
        }

        func advance(_ duration: Duration) async {
            await settle()
            clock.advance(by: duration)
            await settle()
        }

        func settle() async {
            for _ in 0..<20 { await Task.yield() }
        }
    }

    @Test
    func macScheduledRotation_oneDayBeforeDue_noRotationStarted() async {
        let fixture = Fixture()
        let task = fixture.start()
        fixture.authenticated.yield(true)
        await fixture.advance(Self.interval - Self.day)
        #expect(fixture.counter.value == 0)
        task.cancel()
    }

    @Test
    func macScheduledRotation_dueWhileConnected_rotationStartedOnce() async {
        let fixture = Fixture()
        let task = fixture.start()
        fixture.authenticated.yield(true)
        await fixture.advance(Self.interval)
        #expect(fixture.counter.value == 1)
        await fixture.advance(Self.day)
        #expect(fixture.counter.value == 1)
        task.cancel()
    }

    @Test
    func macScheduledRotation_dueWhileOffline_startedOnNextAuthenticatedSession() async {
        let fixture = Fixture()
        let task = fixture.start()
        fixture.authenticated.yield(true)
        await fixture.advance(Self.day)
        fixture.authenticated.yield(false)
        await fixture.advance(Self.interval)
        #expect(fixture.counter.value == 0)
        fixture.authenticated.yield(true)
        await fixture.settle()
        #expect(fixture.counter.value == 1)
        task.cancel()
    }

    @Test
    func macScheduledRotation_afterSuccess_nextDueIsNowPlusInterval() async {
        let fixture = Fixture()
        let task = fixture.start()
        fixture.authenticated.yield(true)
        await fixture.advance(Self.interval)
        #expect(fixture.counter.value == 1)
        #expect(fixture.store.get() == fixture.dates.now().addingTimeInterval(30 * 86_400))
        task.cancel()
    }

    @Test
    func macScheduledRotation_appRelaunch_persistedDueHonoured() async {
        let relaunchDue = Date(timeIntervalSince1970: 0).addingTimeInterval(86_400)
        let fixture = Fixture(store: MemoryStore(relaunchDue))
        let task = fixture.start()
        fixture.authenticated.yield(true)
        await fixture.advance(Self.day - .seconds(1))
        #expect(fixture.counter.value == 0)
        await fixture.advance(.seconds(1))
        #expect(fixture.counter.value == 1)
        task.cancel()
    }
}
