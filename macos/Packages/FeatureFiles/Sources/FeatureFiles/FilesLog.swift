import os
import TandemProtocol

/// DEBUG-only state-transition log for the FILES channel. Event names and reason codes only;
/// never file names, contents or paths (invariant 7).
enum FilesLog {
    #if DEBUG
    private static let logger = Logger(subsystem: "dev.tandem", category: "files")
    #endif

    static func event(_ event: StaticString) {
        #if DEBUG
        logger.debug("\(event, privacy: .public)")
        #endif
    }

    static func event(_ event: StaticString, reason: Tandem_V1_TransferReason) {
        #if DEBUG
        logger.debug("\(event, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        #endif
    }
}
