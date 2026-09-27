/// The one production ``ListenerControl`` (E20-10, E20-11), wrapping the existing
/// ``ListenerController``/``NWListenerFactory`` so ``SleepWakeController`` and
/// ``PathChangeController`` can drive the real Mac listener without either knowing about
/// `Network` at all: ``stop()`` stops accepting new connections and cancels every currently open
/// one (``ConnectionAdmission/cancelAllReady()``, moving each to `Disconnected`, E12-09), and
/// ``start()`` rebinds by asking ``ListenerController`` for a fresh listener and admission actor.
/// Never runs two listeners at once: ``start()`` is a no-op while one is already tracked here.
public actor ProductionListenerControl: ListenerControl {

    public enum StartError: Error, Sendable, Equatable {
        /// The identity was not ``IdentityState/ready(_:)`` when `start()` was called.
        case identityNotReady
    }

    private let listenerController: ListenerController
    private var current: ListenerController.StartedListener?

    /// - Parameter initiallyStarted: An already-running listener/admission pair, if the caller
    ///   started one synchronously up front (as `HarnessHooks` does, so a startup failure still
    ///   fails the process immediately). `stop()`/`start()` manage it from here on; omit this to
    ///   have this instance perform the first `start()` itself.
    public init(
        listenerController: ListenerController,
        initiallyStarted: ListenerController.StartedListener? = nil
    ) {
        self.listenerController = listenerController
        self.current = initiallyStarted
    }

    public func start() async throws {
        guard current == nil else { return }
        guard let started = try listenerController.start() else {
            throw StartError.identityNotReady
        }
        current = started
    }

    public func stop() async {
        guard let started = current else { return }
        current = nil
        await started.admission.cancelAllReady()
        started.listener.cancel()
    }
}
