import os

/// DEBUG-only state-transition log for mirrored notifications. Event names only; never titles,
/// bodies, package names or senders (invariant 7).
enum NotificationsLog {
    #if DEBUG
    private static let logger = Logger(subsystem: "dev.tandem", category: "notifications")
    #endif

    static func event(_ event: StaticString) {
        #if DEBUG
        logger.debug("\(event, privacy: .public)")
        #endif
    }
}
