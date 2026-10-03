import FeatureCalls

/// Test fixture (E52-06): records every ``CallAlertPresenter`` call instead of posting a real
/// notification.
actor RecordingCallAlertPresenter: CallAlertPresenter {
    struct Presented: Sendable, Equatable {
        let callId: String
        let title: String
        let body: String
    }

    private(set) var presented: [Presented] = []
    private(set) var removedCallIds: [String] = []

    nonisolated let responses: AsyncStream<CallAlertResponse>
    private let responsesContinuation: AsyncStream<CallAlertResponse>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<CallAlertResponse>.makeStream(bufferingPolicy: .unbounded)
        responses = stream
        responsesContinuation = continuation
    }

    func present(callId: String, title: String, body: String) async {
        presented.append(Presented(callId: callId, title: title, body: body))
    }

    func remove(callId: String) async {
        removedCallIds.append(callId)
    }

    func inject(_ response: CallAlertResponse) {
        responsesContinuation.yield(response)
    }
}
