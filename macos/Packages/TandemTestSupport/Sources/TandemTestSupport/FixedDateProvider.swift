import Foundation

/// Shape of the production wall-clock seam: a `@Sendable` closure returning `Date`,
/// injected via `init` instead of calling `Date()`/`Date.now` directly.
public typealias DateProvider = @Sendable () -> Date

/// A `DateProvider` whose wall-clock value tracks a ``ManualTestClock``: advancing
/// the clock advances the date this provider returns, from a fixed `epoch`.
public final class FixedDateProvider: Sendable {
    private let clock: ManualTestClock
    private let epoch: Date

    public init(clock: ManualTestClock, epoch: Date = Date(timeIntervalSince1970: 0)) {
        self.clock = clock
        self.epoch = epoch
    }

    public func now() -> Date {
        epoch.addingTimeInterval(clock.now.secondsSinceStart)
    }

    /// The provider as a `DateProvider` closure, ready to hand to a production init.
    public var provider: DateProvider {
        { [clock, epoch] in
            epoch.addingTimeInterval(clock.now.secondsSinceStart)
        }
    }
}
