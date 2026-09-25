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
        verify: @escaping @Sendable sec_protocol_verify_t
    ) throws -> NWListener {
        lock.lock()
        count += 1
        lock.unlock()
        throw ListenerFactoryError.invalidIdentity
    }
}
