/// Observes the Mac Focus state (E72-03 design note). `changes` yields `true` when a Focus becomes
/// active and `false` when it ends; a production implementation polls `INFocusStatusCenter`
/// (``IntentsFocusStateSource``), tests use ``RecordingFocusStateSource``.
public protocol FocusStateSource: Sendable {
    var changes: AsyncStream<Bool> { get }
}
