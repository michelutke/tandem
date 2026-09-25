@testable import TandemPairing

/// Deterministic `LocalAddressSource` fake: returns a fixed, injected address list instead of
/// enumerating real interfaces (E14-01).
struct FakeLocalAddressSource: LocalAddressSource {
    let addresses: [String]

    func currentAddresses() -> [String] {
        addresses
    }
}
