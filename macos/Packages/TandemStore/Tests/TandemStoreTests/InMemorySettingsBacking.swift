import Synchronization
import TandemStore

/// In-memory fake for `SettingsBacking` (E13-08). Lets `SettingsStore` unit tests exercise a "new
/// store instance on the same suite" by constructing a second `SettingsStore` over the same fake
/// instance, without ever touching `UserDefaults` (real or `.standard`).
final class InMemorySettingsBacking: SettingsBacking, @unchecked Sendable {
    private struct State {
        var bools: [String: Bool] = [:]
        var strings: [String: String] = [:]
    }

    private let state = Mutex(State())

    func bool(forKey key: String) -> Bool? {
        state.withLock { $0.bools[key] }
    }

    func setBool(_ value: Bool, forKey key: String) {
        state.withLock { $0.bools[key] = value }
    }

    func string(forKey key: String) -> String? {
        state.withLock { $0.strings[key] }
    }

    func setString(_ value: String, forKey key: String) {
        state.withLock { $0.strings[key] = value }
    }
}
