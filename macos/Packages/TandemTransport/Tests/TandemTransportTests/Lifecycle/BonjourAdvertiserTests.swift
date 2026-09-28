import Foundation
import Network
import Synchronization
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemTransport

/// E21-02 (SPEC.md "Discovery TXT record"): ``BonjourAdvertiser`` computes today's rotating id via
/// ``DiscoveryRotatingId`` from an injected ``DateProvider``/`Clock<Duration>` -- never a real
/// wall-clock read or sleep -- and republishes exactly at the UTC day boundary, against a
/// recording ``FakeBonjourPublisher`` this file drives directly.
@Suite("BonjourAdvertiser")
struct BonjourAdvertiserTests {

    private static let secondsPerDay: TimeInterval = 86_400
    private static let port: UInt16 = 4433

    @Test
    func bonjourAdvertiser_start_txtHasOnlyVersionAndIdKeys() async throws {
        let fingerprint = Data(repeating: 0xAB, count: 32)
        let publisher = FakeBonjourPublisher()
        let dateProvider = FixedDateProvider(clock: ManualTestClock())
        let advertiser = BonjourAdvertiser(
            publisher: publisher, macSpkiFingerprint: fingerprint, port: Self.port,
            dateProvider: dateProvider.provider
        )

        await advertiser.start()
        await settle()

        let lastCall = try #require(publisher.lastPublishCall)
        let txtRecord = NWTXTRecord(lastCall.txtRecord)
        #expect(Set(txtRecord.dictionary.keys) == Set(["v", "id"]))
        #expect(txtRecord.dictionary["v"] == "1")
    }

    @Test
    func bonjourAdvertiser_utcMidnightCrossed_republishesNewIdWithin1s() async {
        let fingerprint = Data(repeating: 0xCD, count: 32)
        let publisher = FakeBonjourPublisher()
        let clock = ManualTestClock()
        let dateProvider = FixedDateProvider(
            clock: clock, epoch: Date(timeIntervalSince1970: Self.secondsPerDay - 5)
        )
        let advertiser = BonjourAdvertiser(
            publisher: publisher, macSpkiFingerprint: fingerprint, port: Self.port,
            dateProvider: dateProvider.provider, clock: clock
        )

        await advertiser.start()
        await settle()

        #expect(publisher.publishCallCount == 1)
        #expect(
            publisher.lastPublishCall?.instanceName
                == DiscoveryRotatingId.computeHex(macSpkiFingerprint: fingerprint, dayIndex: 0)
        )

        clock.advance(by: .seconds(5))
        await settle()

        #expect(publisher.publishCallCount == 2)
        #expect(
            publisher.lastPublishCall?.instanceName
                == DiscoveryRotatingId.computeHex(macSpkiFingerprint: fingerprint, dayIndex: 1)
        )
    }

    @Test
    func bonjourAdvertiser_dayRefresh_existingConnectionsNotCancelled() async {
        let fingerprint = Data(repeating: 0xEF, count: 32)
        let publisher = FakeBonjourPublisher()
        let clock = ManualTestClock()
        let dateProvider = FixedDateProvider(
            clock: clock, epoch: Date(timeIntervalSince1970: Self.secondsPerDay - 5)
        )
        let advertiser = BonjourAdvertiser(
            publisher: publisher, macSpkiFingerprint: fingerprint, port: Self.port,
            dateProvider: dateProvider.provider, clock: clock
        )

        await advertiser.start()
        await settle()
        clock.advance(by: .seconds(5))
        await settle()

        // `BonjourPublisher` has no listener-affecting method at all by design (this package's
        // `BonjourPublisher.swift`): a day refresh only ever calls `publish`, so there is nothing
        // here that could even try to cancel an open control connection.
        #expect(publisher.unpublishCallCount == 0)
    }

    @Test
    func bonjourAdvertiser_timeZoneUtcPlus14_usesUtcDayIndex() async {
        let fingerprint = Data(repeating: 0x12, count: 32)
        let publisher = FakeBonjourPublisher()
        // 2025-06-30T23:00:00Z: the UTC calendar date is 2025-06-30, but in UTC+14 (POSIX
        // "Etc/GMT-14" -- its sign is inverted from the common name) the local wall-clock date is
        // already 2025-07-01. A Calendar/TimeZone-routed dayIndex would disagree with a
        // UTC-seconds-only one at this instant; proving the published id matches the latter
        // proves the production code never routes through Calendar/TimeZone, without mutating any
        // global process state.
        let unixSecondsUtc: Int64 = 1_751_324_400
        let dateProvider = FixedDateProvider(
            clock: ManualTestClock(), epoch: Date(timeIntervalSince1970: TimeInterval(unixSecondsUtc))
        )
        let advertiser = BonjourAdvertiser(
            publisher: publisher, macSpkiFingerprint: fingerprint, port: Self.port,
            dateProvider: dateProvider.provider
        )

        await advertiser.start()
        await settle()

        let expectedDayIndex = DiscoveryRotatingId.dayIndex(unixSecondsUtc: unixSecondsUtc)
        let expectedIdHex = DiscoveryRotatingId.computeHex(
            macSpkiFingerprint: fingerprint, dayIndex: expectedDayIndex
        )
        #expect(publisher.lastPublishCall?.instanceName == expectedIdHex)
    }

    @Test
    func bonjourAdvertiser_instanceName_derivedFromRotatingIdOnly() async {
        let fingerprint = Data(repeating: 0x34, count: 32)
        let publisher = FakeBonjourPublisher()
        let clock = ManualTestClock()
        let dateProvider = FixedDateProvider(
            clock: clock, epoch: Date(timeIntervalSince1970: Self.secondsPerDay - 5)
        )
        let advertiser = BonjourAdvertiser(
            publisher: publisher, macSpkiFingerprint: fingerprint, port: Self.port,
            dateProvider: dateProvider.provider, clock: clock
        )

        await advertiser.start()
        await settle()
        clock.advance(by: .seconds(5))
        await settle()

        let expectedDayZeroId = DiscoveryRotatingId.computeHex(macSpkiFingerprint: fingerprint, dayIndex: 0)
        let expectedDayOneId = DiscoveryRotatingId.computeHex(macSpkiFingerprint: fingerprint, dayIndex: 1)

        #expect(publisher.publishCalls.map(\.instanceName) == [expectedDayZeroId, expectedDayOneId])
    }

    /// Regression for a real lifecycle bug: `stop()` racing an in-flight `refreshForCurrentDay()`
    /// must not leave a day-boundary timer armed -- otherwise a stopped advertiser keeps
    /// republishing at every subsequent UTC midnight forever.
    @Test
    func bonjourAdvertiser_stopDuringRefresh_doesNotRepublishAtNextMidnight() async {
        let fingerprint = Data(repeating: 0xEF, count: 32)
        let publisher = FakeBonjourPublisher()
        publisher.armGate()
        let clock = ManualTestClock()
        let dateProvider = FixedDateProvider(clock: clock)
        let advertiser = BonjourAdvertiser(
            publisher: publisher, macSpkiFingerprint: fingerprint, port: Self.port,
            dateProvider: dateProvider.provider, clock: clock
        )

        let startTask = Task { await advertiser.start() }
        await settle()
        // `start()` is suspended inside `publisher.publish` (the gate); `stop()` races it here.
        await advertiser.stop()
        publisher.releaseGate()
        await startTask.value
        await settle()

        clock.advance(by: .seconds(Self.secondsPerDay))
        await settle()

        // Exactly the one publish from `start()` -- stop() must have prevented any timer from
        // ever being armed, so crossing a full day boundary republishes nothing.
        #expect(publisher.publishCallCount == 1)
    }

    /// Yields several times so the actor's background refresh `Task` has a chance to run, without
    /// an artificial wall-clock sleep.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// Recording ``BonjourPublisher`` fake, standing in for ``NetServiceBonjourPublisher`` in
/// ``BonjourAdvertiserTests`` -- records every `publish`/`unpublish` call with its arguments,
/// mirroring `SleepWakeControllerTests`' `FakeListenerControl`.
final class FakeBonjourPublisher: BonjourPublisher, @unchecked Sendable {
    struct PublishCall: Sendable, Equatable {
        let instanceName: String
        let port: UInt16
        let txtRecord: Data
    }

    private struct State {
        var publishCalls: [PublishCall] = []
        var unpublishCallCount = 0
    }

    private let state = Mutex(State())

    /// A test can arm this gate so `publish` suspends until `releaseGate()` is called, to
    /// reproduce a `stop()` racing an in-flight `publish` deterministically.
    private let gate = AsyncStream<Void>.makeStream()
    private let gateArmed = Mutex(false)

    /// No test here drives ``BonjourAdvertiser`` through a publish error -- that's
    /// `LocalNetworkPermissionViewModelTests` (TandemAppTests), which feeds a plain
    /// `AsyncStream<BonjourPublishError>` directly rather than through this fake. Just an
    /// already-finished, empty stream to satisfy ``BonjourPublisher`` conformance.
    let errors = AsyncStream<BonjourPublishError>.makeStream().stream

    func armGate() {
        gateArmed.withLock { $0 = true }
    }

    func releaseGate() {
        gate.continuation.yield()
    }

    func publish(instanceName: String, port: UInt16, txtRecord: Data) async {
        if gateArmed.withLock({ $0 }) {
            var iterator = gate.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        state.withLock {
            $0.publishCalls.append(PublishCall(instanceName: instanceName, port: port, txtRecord: txtRecord))
        }
    }

    func unpublish() async {
        state.withLock { $0.unpublishCallCount += 1 }
    }

    var publishCalls: [PublishCall] {
        state.withLock { $0.publishCalls }
    }

    var publishCallCount: Int {
        publishCalls.count
    }

    var unpublishCallCount: Int {
        state.withLock { $0.unpublishCallCount }
    }

    var lastPublishCall: PublishCall? {
        publishCalls.last
    }
}
