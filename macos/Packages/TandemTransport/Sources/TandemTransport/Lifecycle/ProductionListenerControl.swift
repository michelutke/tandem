/// The one production ``ListenerControl`` (E20-10, E20-11), wrapping the existing
/// ``ListenerController``/``NWListenerFactory`` so ``SleepWakeController`` and
/// ``PathChangeController`` can drive the real Mac listener without either knowing about
/// `Network` at all: ``stop()`` stops accepting new connections and cancels every currently open
/// one (``ConnectionAdmission/cancelAllReady()``, moving each to `Disconnected`, E12-09), and
/// ``start()`` rebinds by asking ``ListenerController`` for a fresh listener and admission actor.
/// Never runs two listeners at once: ``start()`` is a no-op while one is already tracked here, and
/// ``start()``, ``stop()`` and ``restart()`` run one at a time in call order, so a rebind never
/// races a stop for the preferred port. The blocking bind retry runs off this actor.
public actor ProductionListenerControl: ListenerControl {

    public enum StartError: Error, Sendable, Equatable {
        /// The identity was not ``IdentityState/ready(_:)`` when `start()` was called.
        case identityNotReady
    }

    private let listenerController: ListenerController
    private var current: ListenerController.StartedListener?
    private let onStarted: (@Sendable (ListenerController.StartedListener) async -> Void)?
    private let onStopped: (@Sendable () async -> Void)?
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameter initiallyStarted: An already-running listener/admission pair, if the caller
    ///   started one synchronously up front (as `HarnessHooks` does, so a startup failure still
    ///   fails the process immediately). `stop()`/`start()` manage it from here on; omit this to
    ///   have this instance perform the first `start()` itself.
    /// - Parameter onStarted: Awaited with every listener ``start()`` rebinds, so a consumer of the
    ///   listener's port (the pairing QR, the Bonjour advertisement) never keeps a stale one.
    /// - Parameter onStopped: Awaited after ``stop()`` stopped a running listener, so a consumer
    ///   (the Bonjour advertisement) is withdrawn in order with the starts that follow.
    public init(
        listenerController: ListenerController,
        initiallyStarted: ListenerController.StartedListener? = nil,
        onStarted: (@Sendable (ListenerController.StartedListener) async -> Void)? = nil,
        onStopped: (@Sendable () async -> Void)? = nil
    ) {
        self.listenerController = listenerController
        self.current = initiallyStarted
        self.onStarted = onStarted
        self.onStopped = onStopped
    }

    public func start() async throws {
        await acquire()
        defer { release() }
        try await startLocked()
    }

    public func stop() async {
        await acquire()
        defer { release() }
        await stopLocked()
    }

    public func restart() async throws {
        await acquire()
        defer { release() }
        await stopLocked()
        try await startLocked()
    }

    private func startLocked() async throws {
        guard current == nil else { return }
        let controller = listenerController
        let started = try await Task.detached { try controller.start() }.value
        guard let started else { throw StartError.identityNotReady }
        current = started
        await onStarted?(started)
    }

    private func stopLocked() async {
        guard let started = current else { return }
        current = nil
        started.listener.cancel()
        await started.admission.cancelAllReady()
        await onStopped?()
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
