import Testing
@testable import TandemTransport

@MainActor
struct ListenerStartupModelTests {
    private final class Script {
        var results: [Result<Int, ListenerStartFailure>]
        var calls = 0

        init(_ results: [Result<Int, ListenerStartFailure>]) {
            self.results = results
        }

        func next() -> Result<Int, ListenerStartFailure> {
            calls += 1
            return results.removeFirst()
        }
    }

    @Test func start_success_isStartedAndReportsLifecycle() {
        let script = Script([.success(7)])
        var started: [Int] = []
        let model = ListenerStartupModel<Int>(start: { script.next() }, onStarted: { started.append($0) })

        model.start()

        #expect(model.phase == .started)
        #expect(model.lifecycle == 7)
        #expect(model.generation == 1)
        #expect(started == [7])
    }

    @Test func retry_afterFailureThenSuccess_becomesStarted() {
        let script = Script([.failure(.init(.keychainAccess)), .success(1)])
        let model = ListenerStartupModel<Int>(start: { script.next() })

        model.start()
        #expect(model.phase == .failed(.keychainAccess))

        model.retry()
        #expect(model.phase == .started)
        #expect(model.lifecycle == 1)
        #expect(model.generation == 1)
    }

    @Test func retry_afterFailureThenFailure_staysFailedWithNewReason() {
        let script = Script([.failure(.init(.keychainAccess)), .failure(.init(.portUnavailable))])
        let model = ListenerStartupModel<Int>(start: { script.next() })

        model.start()
        model.retry()

        #expect(model.phase == .failed(.portUnavailable))
        #expect(model.lifecycle == nil)
        #expect(model.generation == 0)
    }

    @Test func retry_whenStarted_doesNotStartAgain() {
        let script = Script([.success(1)])
        let model = ListenerStartupModel<Int>(start: { script.next() })
        model.start()

        model.retry()
        model.start()

        #expect(script.calls == 1)
        #expect(model.generation == 1)
    }

    @Test func retry_beforeAnyStart_isNoOp() {
        let script = Script([.success(1)])
        let model = ListenerStartupModel<Int>(start: { script.next() })

        model.retry()

        #expect(script.calls == 0)
        #expect(model.phase == .notStarted)
    }

    @Test func start_reentrantFromStartAction_isGuarded() {
        var model: ListenerStartupModel<Int>?
        var calls = 0
        model = ListenerStartupModel<Int>(start: {
            calls += 1
            model?.start()
            return .success(1)
        })

        model?.start()

        #expect(calls == 1)
    }

    @Test func retryOnActivation_keychainAccessFailure_doesNotRetry() {
        let script = Script([.failure(.init(.keychainAccess)), .success(1)])
        let model = ListenerStartupModel<Int>(start: { script.next() })
        model.start()

        model.retryOnActivation()

        #expect(script.calls == 1)
        #expect(model.phase == .failed(.keychainAccess))
    }

    @Test func retryOnActivation_portFailure_retriesOnce() {
        let script = Script([.failure(.init(.portUnavailable)), .success(1)])
        let model = ListenerStartupModel<Int>(start: { script.next() })
        model.start()

        model.retryOnActivation()

        #expect(script.calls == 2)
        #expect(model.phase == .started)
    }

    @Test func classify_similarLookingCode_isNotKeychainAccess() {
        #expect(ListenerFailureReason.classify(identityError: "unhandled(status: -1280)") == .identityUnavailable)
        #expect(ListenerFailureReason.classify(identityError: "unhandled(status: -108)") == .identityUnavailable)
    }

    @Test(arguments: [
        "authFailed", "locked", "unhandled(status: -128)", "unhandled(status: -25293)", "unhandled(status: -25308)"
    ])
    func classify_keychainAccessErrors_isKeychainAccess(description: String) {
        #expect(ListenerFailureReason.classify(identityError: description) == .keychainAccess)
    }

    @Test func classify_otherIdentityError_isIdentityUnavailable() {
        #expect(ListenerFailureReason.classify(identityError: "itemNotFound") == .identityUnavailable)
    }

    @Test func classify_bindError_isPortUnavailable() {
        #expect(ListenerFailureReason.classify(listenerError: ListenerBindError.bindFailed) == .portUnavailable)
    }

    @Test func message_everyReason_isNonEmptySentence() {
        for reason in [ListenerFailureReason.keychainAccess, .identityUnavailable, .portUnavailable, .unknown] {
            #expect(reason.message.hasSuffix("."))
        }
    }
}
