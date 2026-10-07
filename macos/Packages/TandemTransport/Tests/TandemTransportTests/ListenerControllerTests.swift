import Foundation
import Network
import Security
import Testing
@testable import TandemTransport

@Suite("ListenerController")
struct ListenerControllerTests {

    @Test(arguments: [
        FixedIdentityStateProvider(state: .missing),
        FixedIdentityStateProvider(state: .error("boom"))
    ])
    func listenerController_identityErrorState_listenerFactoryNeverInvoked(
        provider: FixedIdentityStateProvider
    ) throws {
        let factory = RecordingListenerFactory()
        let controller = ListenerController(
            identityStateProvider: provider,
            listenerFactory: factory,
            port: .any,
            verify: { _, _, complete in complete(true) }
        )

        let listener = try controller.start()

        #expect(listener == nil)
        #expect(factory.invocationCount == 0)
    }
}

struct FixedIdentityStateProvider: IdentityStateProvider, CustomStringConvertible {
    let state: IdentityState

    var identityState: IdentityState { state }

    var description: String {
        switch state {
        case .ready: return "ready"
        case .missing: return "missing"
        case .error(let reason): return "error(\(reason))"
        }
    }
}

final class RecordingListenerFactory: ListenerFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func makeListener(
        identity: SecIdentity,
        port: NWEndpoint.Port,
        verify: @escaping @Sendable sec_protocol_verify_t,
        admission: ConnectionAdmission
    ) throws -> NWListener {
        lock.lock()
        count += 1
        lock.unlock()
        throw ListenerFactoryError.invalidIdentity
    }
}

@Suite("ListenerController port persistence")
struct ListenerControllerPortTests {

    @Test func start_preferredPortPersisted_boundBeforeAnyOther() throws {
        let harness = PortHarness(preferred: 50_123, outcomes: [.ready(port: 50_123)])

        try harness.controller.start()

        #expect(harness.factory.requestedPorts == [50_123])
        #expect(harness.store.persisted == [50_123])
    }

    @Test func start_preferredPortTaken_fallsBackToAnyAndPersistsNewPort() throws {
        let harness = PortHarness(preferred: 50_123, outcomes: [.failed, .ready(port: 61_000)])

        try harness.controller.start()

        #expect(harness.factory.requestedPorts == [50_123, 0])
        #expect(harness.store.persisted == [61_000])
    }

    @Test func start_noPersistedPort_bindsAnyAndPersists() throws {
        let harness = PortHarness(preferred: nil, outcomes: [.ready(port: 62_000)])

        try harness.controller.start()

        #expect(harness.factory.requestedPorts == [0])
        #expect(harness.store.persisted == [62_000])
    }

    @Test func start_everyBindFails_throwsBindFailed() {
        let harness = PortHarness(preferred: nil, outcomes: [.failed])

        #expect(throws: ListenerBindError.bindFailed) { try harness.controller.start() }
        #expect(harness.store.persisted.isEmpty)
    }
}

private final class PortHarness {
    let factory = PortRecordingFactory()
    let store: InMemoryListenerPortStore
    let controller: ListenerController
    private let keychain: TemporaryKeychain

    init(preferred: UInt16?, outcomes: [ListenerBindOutcome]) {
        // swiftlint:disable:next force_try
        keychain = try! TemporaryKeychain()
        store = InMemoryListenerPortStore(preferred: preferred)
        // swiftlint:disable:next force_try
        let identity = try! keychain.makeSecIdentity()
        controller = ListenerController(
            identityStateProvider: FixedIdentityStateProvider(state: .ready(identity)),
            listenerFactory: factory,
            port: .any,
            verify: { _, _, complete in complete(true) },
            portStore: store,
            binder: ScriptedBinder(outcomes: outcomes)
        )
    }

    deinit { keychain.cleanup() }
}

private final class InMemoryListenerPortStore: ListenerPortStore, @unchecked Sendable {
    private let lock = NSLock()
    private let preferred: UInt16?
    private var saved: [UInt16] = []

    init(preferred: UInt16?) { self.preferred = preferred }

    var preferredPort: UInt16? { preferred }

    var persisted: [UInt16] {
        lock.lock()
        defer { lock.unlock() }
        return saved
    }

    func persist(_ port: UInt16) {
        lock.lock()
        saved.append(port)
        lock.unlock()
    }
}

private final class ScriptedBinder: ListenerBinder, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [ListenerBindOutcome]

    init(outcomes: [ListenerBindOutcome]) { self.outcomes = outcomes }

    func bind(_ listener: NWListener) -> ListenerBindOutcome {
        lock.lock()
        defer { lock.unlock() }
        return outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
    }
}

private final class PortRecordingFactory: ListenerFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var ports: [UInt16] = []

    var requestedPorts: [UInt16] {
        lock.lock()
        defer { lock.unlock() }
        return ports
    }

    func makeListener(
        identity: SecIdentity,
        port: NWEndpoint.Port,
        verify: @escaping @Sendable sec_protocol_verify_t,
        admission: ConnectionAdmission
    ) throws -> NWListener {
        lock.lock()
        ports.append(port.rawValue)
        lock.unlock()
        return try NWListener(using: .tcp, on: .any)
    }
}
