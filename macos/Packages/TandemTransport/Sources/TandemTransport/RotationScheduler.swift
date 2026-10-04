import Foundation
import os

/// Result of one scheduled rotation attempt; only `committed` moves the next due instant.
enum RotationOutcome: Equatable, Sendable {
    case committed
    case notCommitted
}

/// Persists the instant the next scheduled rotation is due (E70-12).
protocol NextRotationDueStore: Sendable {
    func get() -> Date?
    func set(_ due: Date)
}

/// ``NextRotationDueStore`` backed by `url`: epoch seconds, replaced atomically so a crash leaves
/// either the old or the new instant. A missing or unparsable file reads as no due instant.
struct FileNextRotationDueStore: NextRotationDueStore {
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "RotationScheduler")

    let url: URL

    func get() -> Date? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func set(_ due: Date) {
        do {
            try String(due.timeIntervalSince1970).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Self.logger.error("persisting next rotation due failed")
        }
    }
}

/// Periodic key rotation for the Mac identity (E70-12, SPEC.md #key-rotation, mirrors E70-07).
/// ``run(authenticated:)`` suspends for the life of its stream and counts down only while the
/// session is authenticated: a due instant that passes offline is acted on when the next
/// authenticated session starts. The due instant lives in `store` (first run: now + `interval`) and
/// moves to now + `interval` after ``RotationOutcome/committed``; any other outcome leaves it due,
/// to be retried on the next authenticated session. Never logs keys or fingerprints.
actor RotationScheduler {
    private let clock: any Clock<Duration>
    private let dateProvider: DateProvider
    private let interval: Duration
    private let store: any NextRotationDueStore
    private let rotate: @Sendable () async -> RotationOutcome

    init(
        clock: any Clock<Duration>,
        dateProvider: @escaping DateProvider,
        interval: Duration,
        store: any NextRotationDueStore,
        rotate: @escaping @Sendable () async -> RotationOutcome
    ) {
        self.clock = clock
        self.dateProvider = dateProvider
        self.interval = interval
        self.store = store
        self.rotate = rotate
    }

    func run(authenticated: AsyncStream<Bool>) async {
        var countdown: Task<Void, Never>?
        for await isAuthenticated in authenticated {
            countdown?.cancel()
            countdown = isAuthenticated ? Task { await rotateWhenDue() } : nil
        }
        countdown?.cancel()
    }

    private func rotateWhenDue() async {
        while !Task.isCancelled {
            let due = store.get() ?? firstDue()
            let wait = due.timeIntervalSince(dateProvider())
            if wait > 0 {
                do { try await clock.sleep(for: .seconds(wait)) } catch { return }
            }
            guard !Task.isCancelled, await rotate() == .committed else { return }
            store.set(nextDue())
        }
    }

    private func firstDue() -> Date {
        let due = nextDue()
        store.set(due)
        return due
    }

    private func nextDue() -> Date {
        dateProvider().addingTimeInterval(Double(interval.components.seconds))
    }
}
