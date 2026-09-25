import Foundation

/// Testability seam for settings persistence (E13-08), shaped after `UserDefaults`'s own
/// `bool`/`string`/`set(_:forKey:)` API so `UserDefaultsSettingsBacking` is a thin pass-through.
/// `SettingsStore` depends on `any SettingsBacking` via init, never on `UserDefaults` directly, so
/// unit tests run against an in-memory fake (`InMemorySettingsBacking`) and never touch
/// `UserDefaults.standard`.
public protocol SettingsBacking: Sendable {
    func bool(forKey key: String) -> Bool?
    func setBool(_ value: Bool, forKey key: String)

    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}

/// Production `SettingsBacking` over a named `UserDefaults` suite -- never `UserDefaults.standard`
/// -- so app settings never collide with another suite and a test suite can be created and torn
/// down without touching real user state. `@unchecked Sendable` because `UserDefaults` itself
/// isn't marked `Sendable` even though Apple documents it as safe to use from multiple threads.
public struct UserDefaultsSettingsBacking: SettingsBacking, @unchecked Sendable {
    private let defaults: UserDefaults

    public init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    public func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    public func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

/// A preference key with its declared default (E13-08 acceptance: an absent key returns this
/// value).
public struct SettingsKey<Value: Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(name: String, defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// Typed get/set API over a settings suite (E13-08 scaffold). Holds only non-secret preferences --
/// pairing secrets and identity material live in `TrustStore`/Keychain, never here.
public struct SettingsStore: Sendable {
    private let backing: any SettingsBacking

    public init(backing: any SettingsBacking) {
        self.backing = backing
    }

    public func bool(_ key: SettingsKey<Bool>) -> Bool {
        backing.bool(forKey: key.name) ?? key.defaultValue
    }

    public func set(_ value: Bool, for key: SettingsKey<Bool>) {
        backing.setBool(value, forKey: key.name)
    }

    public func string(_ key: SettingsKey<String>) -> String {
        backing.string(forKey: key.name) ?? key.defaultValue
    }

    public func set(_ value: String, for key: SettingsKey<String>) {
        backing.setString(value, forKey: key.name)
    }
}
