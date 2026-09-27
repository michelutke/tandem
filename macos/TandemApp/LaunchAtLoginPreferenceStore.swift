import Foundation

/// Whether the user has ever explicitly set the launch-at-login toggle -- gates the "default ON
/// after first successful pairing" behavior (backlog E22-03): once the user (or that default) has
/// acted once, ``LaunchAtLoginViewModel`` never overrides their choice again.
protocol LaunchAtLoginPreferenceStore: AnyObject {
    var hasUserSetToggle: Bool { get set }
}

/// The production ``LaunchAtLoginPreferenceStore``, backed by `UserDefaults`.
final class UserDefaultsLaunchAtLoginPreferenceStore: LaunchAtLoginPreferenceStore {
    private static let key = "LaunchAtLoginHasUserSetToggle"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasUserSetToggle: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
