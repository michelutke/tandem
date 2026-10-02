#if canImport(os)
import os
#endif

/// E20-12 reconnect-harness markers: one `TandemReconnect event=<disconnected|dead|ready>` unified-log
/// line per connection transition, parsed by `tools/reconnect-harness`. Carries no peer data.
public protocol ReconnectMarkers: Sendable {
    func disconnected()
    func dead()
    func ready()
}

public struct NoOpReconnectMarkers: ReconnectMarkers {
    public init() {}

    public func disconnected() {}
    public func dead() {}
    public func ready() {}
}

#if canImport(os)
public struct OSLogReconnectMarkers: ReconnectMarkers {
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "Reconnect")

    public init() {}

    public func disconnected() { Self.logger.notice("TandemReconnect event=disconnected") }
    public func dead() { Self.logger.notice("TandemReconnect event=dead") }
    public func ready() { Self.logger.notice("TandemReconnect event=ready") }
}
#endif
