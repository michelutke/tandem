import FeatureFocus

final class RecordingFocusStateSource: FocusStateSource, Sendable {
    let changes: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    init() {
        (changes, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .unbounded)
    }

    func emit(_ isOn: Bool) {
        continuation.yield(isOn)
    }

    func finish() {
        continuation.finish()
    }
}
