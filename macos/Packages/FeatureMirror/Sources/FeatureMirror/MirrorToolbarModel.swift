import Observation

/// Drives the mirror window's glass toolbar. Back, Home and Recents go through the window's
/// ``MirrorInputSender``, so they are sent only while its mirror session is active and the window is
/// key (invariant 8); with no sender there is no control and nothing is sent.
@MainActor
@Observable
public final class MirrorToolbarModel {
    private let inputSender: MirrorInputSender?
    private let onStop: @MainActor () -> Void

    public var isControlOn: Bool { inputSender?.isActive == true }

    public init(inputSender: MirrorInputSender?, onStop: @escaping @MainActor () -> Void) {
        self.inputSender = inputSender
        self.onStop = onStop
    }

    public func perform(_ action: MirrorGlobalAction) {
        inputSender?.handle(.global(action))
    }

    public func stop() {
        onStop()
    }
}
