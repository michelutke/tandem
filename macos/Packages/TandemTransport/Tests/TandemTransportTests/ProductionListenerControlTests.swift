import Foundation
import Network
import Security
import Synchronization
import Testing
@testable import TandemTransport

@Suite("ProductionListenerControl")
struct ProductionListenerControlTests {
    private final class StopCounter: Sendable {
        private let count = Mutex(0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    private struct ReadyBinder: ListenerBinder {
        func bind(_ listener: NWListener) -> ListenerBindOutcome { .ready(port: 50_000) }
    }

    private static func controller(identity: IdentityState, factory: any ListenerFactory) -> ListenerController {
        ListenerController(
            identityStateProvider: FixedIdentityStateProvider(state: identity),
            listenerFactory: factory,
            port: .any,
            verify: { _, _, complete in complete(true) },
            binder: ReadyBinder()
        )
    }

    private static func runningListener() throws -> ListenerController.StartedListener {
        ListenerController.StartedListener(
            listener: try NWListener(using: .tcp, on: .any),
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
    }

    @Test
    func productionListenerControl_stop_onStoppedCalledOnceForTheStoppedListener() async throws {
        let stops = StopCounter()
        let control = ProductionListenerControl(
            listenerController: Self.controller(identity: .missing, factory: RecordingListenerFactory()),
            initiallyStarted: try Self.runningListener(),
            onStopped: { stops.increment() }
        )

        await control.stop()
        await control.stop()

        #expect(stops.value == 1)
    }

    @Test
    func productionListenerControl_restartWithoutIdentity_stopsThenThrowsIdentityNotReady() async throws {
        let stops = StopCounter()
        let control = ProductionListenerControl(
            listenerController: Self.controller(identity: .missing, factory: RecordingListenerFactory()),
            initiallyStarted: try Self.runningListener(),
            onStopped: { stops.increment() }
        )

        await #expect(throws: ProductionListenerControl.StartError.identityNotReady) {
            try await control.restart()
        }

        #expect(stops.value == 1)
    }

    @Test
    func productionListenerControl_concurrentStarts_bindsOnce() async throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let factory = CountingListenerFactory()
        let control = ProductionListenerControl(
            listenerController: Self.controller(
                identity: .ready(try keychain.makeSecIdentity()), factory: factory
            )
        )

        async let first: Void = control.start()
        async let second: Void = control.start()
        _ = try await (first, second)
        await control.stop()

        #expect(factory.count == 1)
    }
}

private final class CountingListenerFactory: ListenerFactory, @unchecked Sendable {
    private let made = Mutex(0)
    var count: Int { made.withLock { $0 } }

    func makeListener(
        identity: SecIdentity,
        port: NWEndpoint.Port,
        verify: @escaping @Sendable sec_protocol_verify_t,
        admission: ConnectionAdmission
    ) throws -> NWListener {
        made.withLock { $0 += 1 }
        Thread.sleep(forTimeInterval: 0.05)
        return try NWListener(using: .tcp, on: .any)
    }
}
