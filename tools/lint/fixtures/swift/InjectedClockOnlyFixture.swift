import Foundation

struct InjectedClockOnlyFixture {
    func now() -> Date {
        Date()
    }
}
