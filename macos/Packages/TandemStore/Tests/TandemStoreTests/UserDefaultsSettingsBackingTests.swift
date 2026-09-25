import Foundation
import Testing
@testable import TandemStore

/// Exercises the real `UserDefaults`-backed seam (E13-08). Every test creates its own suite name
/// and removes it afterward, so this never touches `UserDefaults.standard` or leaves state behind.
@Suite("UserDefaultsSettingsBacking")
struct UserDefaultsSettingsBackingTests {

    private static let flag = SettingsKey<Bool>(name: "test.flag", defaultValue: false)

    private func withTestSuite(_ body: (String) throws -> Void) rethrows {
        let suiteName = "com.tandem.settings.test.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        try body(suiteName)
    }

    @Test
    func userDefaultsSettingsBacking_setThenGetNewInstanceSameSuite_returnsSetValue() throws {
        try withTestSuite { suiteName in
            let first = try #require(UserDefaultsSettingsBacking(suiteName: suiteName))
            SettingsStore(backing: first).set(true, for: Self.flag)

            let second = try #require(UserDefaultsSettingsBacking(suiteName: suiteName))
            #expect(SettingsStore(backing: second).bool(Self.flag) == true)
        }
    }

    @Test
    func userDefaultsSettingsBacking_getAbsentKey_returnsDeclaredDefault() throws {
        try withTestSuite { suiteName in
            let backing = try #require(UserDefaultsSettingsBacking(suiteName: suiteName))
            #expect(SettingsStore(backing: backing).bool(Self.flag) == false)
        }
    }
}
