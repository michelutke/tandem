import os

enum LogCategory {
    case pairing
}

private let logger = Logger(subsystem: "com.tandem", category: "pairing")

func logCategory(_ category: LogCategory) {
    logger.notice("\(category, privacy: .public)")
}
