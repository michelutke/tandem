/// Seam over the Mac's single mTLS listener (E12-01, ``ListenerController``) that
/// ``SleepWakeController`` (E20-10) drives across sleep/wake; E20-11 reuses it to rebind the
/// listener on a network path change.
///
/// ``stop()``'s contract covers both halves of the sleep acceptance criterion: it must stop
/// accepting new connections *and* move every open connection to `Disconnected`
/// (`TandemProtocol.ConnectionStateMachine`, E12-09) without crashing or leaking a connection.
/// ``start()`` must leave the listener ready to accept again.
public protocol ListenerControl: Sendable {
    func start() async throws
    func stop() async
}
