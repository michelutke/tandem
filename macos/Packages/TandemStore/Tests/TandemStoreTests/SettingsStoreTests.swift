import Testing
@testable import TandemStore

@Suite("SettingsStore")
struct SettingsStoreTests {

    private static let flag = SettingsKey<Bool>(name: "test.flag", defaultValue: false)
    private static let name = SettingsKey<String>(name: "test.name", defaultValue: "default")

    @Test
    func settingsStore_setThenGetNewInstance_returnsSetValue() {
        let backing = InMemorySettingsBacking()
        let first = SettingsStore(backing: backing)

        first.set(true, for: Self.flag)

        let second = SettingsStore(backing: backing)
        #expect(second.bool(Self.flag) == true)
    }

    @Test
    func settingsStore_getAbsentKey_returnsDeclaredDefault() {
        let store = SettingsStore(backing: InMemorySettingsBacking())

        #expect(store.bool(Self.flag) == false)
        #expect(store.string(Self.name) == "default")
    }

    @Test
    func settingsStore_setThenGetString_returnsSetValue() {
        let store = SettingsStore(backing: InMemorySettingsBacking())

        store.set("custom", for: Self.name)

        #expect(store.string(Self.name) == "custom")
    }
}
