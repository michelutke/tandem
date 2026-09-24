import Synchronization

/// A `Clock` whose passage of time is driven entirely by explicit calls to
/// ``advance(by:)`` — real wall-clock time never elapses it. Sleepers are resumed
/// deterministically, in deadline order, as soon as the advanced `now` reaches or
/// passes their deadline.
public final class ManualTestClock: Clock, Sendable {

    public struct Instant: InstantProtocol, Sendable {
        fileprivate let offset: Duration

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }

        /// The clock's starting instant, before any ``ManualTestClock/advance(by:)`` call.
        public static let start = Instant(offset: .zero)
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State: Sendable {
        var now: Instant
        var sleepers: [Sleeper] = []
        var nextID = 0
        /// Sleepers cancelled before they were parked; resumed with CancellationError on parking.
        var cancelledBeforeParking: Set<Int> = []
    }

    private let state: Mutex<State>

    public init(now: Instant = .start) {
        state = Mutex(State(now: now))
    }

    public var now: Instant {
        state.withLock { $0.now }
    }

    public var minimumResolution: Duration {
        .zero
    }

    /// Number of sleepers currently parked, waiting for ``advance(by:)`` to reach
    /// their deadline. Not part of the public seam surface; exposed for
    /// deterministic assertions in this package's own tests.
    var pendingSleeperCountForTesting: Int {
        state.withLock { $0.sleepers.count }
    }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()

        let id = state.withLock { box -> Int? in
            if box.now >= deadline { return nil }
            box.nextID += 1
            return box.nextID
        }
        guard let id else { return }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let outcome = state.withLock { box -> Result<Bool, CancellationError> in
                    if box.cancelledBeforeParking.remove(id) != nil { return .failure(CancellationError()) }
                    if box.now >= deadline { return .success(true) }
                    box.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .success(false)
                }
                switch outcome {
                case .failure(let error): continuation.resume(throwing: error)
                case .success(true): continuation.resume()
                case .success(false): break
                }
            }
        } onCancel: {
            let cancelled = state.withLock { box -> Sleeper? in
                guard let index = box.sleepers.firstIndex(where: { $0.id == id }) else {
                    box.cancelledBeforeParking.insert(id)
                    return nil
                }
                return box.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Advances `now` by `duration` and resumes, in deadline order, every sleeper
    /// whose deadline has passed.
    public func advance(by duration: Duration) {
        let ready = state.withLock { box -> [Sleeper] in
            box.now = box.now.advanced(by: duration)
            var ready: [Sleeper] = []
            box.sleepers.removeAll { sleeper in
                guard sleeper.deadline <= box.now else { return false }
                ready.append(sleeper)
                return true
            }
            ready.sort { lhs, rhs in
                lhs.deadline == rhs.deadline ? lhs.id < rhs.id : lhs.deadline < rhs.deadline
            }
            return ready
        }
        for sleeper in ready {
            sleeper.continuation.resume()
        }
    }
}

extension ManualTestClock.Instant: Comparable, Hashable {
    public static func == (lhs: ManualTestClock.Instant, rhs: ManualTestClock.Instant) -> Bool {
        lhs.offset == rhs.offset
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(offset)
    }

    /// Elapsed time since the clock's start, in seconds. Used to translate a
    /// ``ManualTestClock`` instant into a wall-clock offset for `FixedDateProvider`.
    var secondsSinceStart: Double {
        let components = offset.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
