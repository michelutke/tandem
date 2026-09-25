import os

private let logger = Logger(subsystem: "com.tandem", category: "pairing")

func logRequest(_ requestId: String) {
    logger.notice("\(requestId, privacy: .public)")
}
