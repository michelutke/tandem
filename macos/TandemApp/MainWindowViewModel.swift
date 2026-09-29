import Foundation
import Observation

/// Persists the sidebar's selected section across launches (backlog E22-09 acceptance: "selection
/// persists across launches"). Shaped after ``LaunchAtLoginPreferenceStore``'s own seam: a small
/// protocol over a single value, backed by `UserDefaults` in production, a plain in-memory fake in
/// tests.
protocol MainWindowSectionStore: AnyObject {
    var selectedSectionID: Int? { get set }
}

/// The production ``MainWindowSectionStore``, backed by `UserDefaults`.
final class UserDefaultsMainWindowSectionStore: MainWindowSectionStore {
    private static let key = "MainWindowSelectedSectionID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedSectionID: Int? {
        get { defaults.object(forKey: Self.key) as? Int }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// The main window's own presentation state (E22-09, ui-spec §7.1): the five numbered sidebar
/// sections, the phone's connection state (online / offline with last-seen), which sections the
/// phone has turned the underlying feature off for, and the persisted selection.
///
/// No paired-session wiring exists yet for ``connectionState``/``disabledSectionIDs`` to react to
/// (E22-02, E23) -- the same gap ``MenuBarViewModel``'s own `stateStream: nil` documents -- so both
/// are supplied by the caller for now; a future issue will observe the real session/status stream
/// the same way ``MenuBarViewModel`` observes ``ConnectionStateMachine``.
@MainActor
@Observable
final class MainWindowViewModel {
    struct Section: Identifiable, Sendable, Equatable {
        let id: Int
        let title: String
    }

    enum ConnectionState: Equatable {
        case online
        case offline(lastSeen: Date)
    }

    /// The five sections in display order (backlog E22-09 acceptance: "Sidebar lists the five
    /// sections").
    static let sections: [Section] = [
        Section(id: 1, title: "Messages"),
        Section(id: 2, title: "Photos"),
        Section(id: 3, title: "Calls"),
        Section(id: 4, title: "Transfers"),
        Section(id: 5, title: "Devices")
    ]

    let deviceName: String
    private(set) var connectionState: ConnectionState
    private(set) var disabledSectionIDs: Set<Int>
    private(set) var selectedSectionID: Int

    private let sectionStore: any MainWindowSectionStore

    init(
        deviceName: String,
        connectionState: ConnectionState,
        disabledSectionIDs: Set<Int> = [],
        sectionStore: any MainWindowSectionStore
    ) {
        self.deviceName = deviceName
        self.connectionState = connectionState
        self.disabledSectionIDs = disabledSectionIDs
        self.sectionStore = sectionStore
        let restored = sectionStore.selectedSectionID
        selectedSectionID = Self.sections.first(where: { $0.id == restored })?.id ?? Self.sections[0].id
    }

    var isOffline: Bool {
        if case .offline = connectionState { return true }
        return false
    }

    /// The sidebar's connection-state line (acceptance: "Offline · seen HH:MM"; ui-spec §7.1's own
    /// "Connected." otherwise).
    var connectionStateText: String {
        switch connectionState {
        case .online:
            return "Connected."
        case .offline(let lastSeen):
            return "Offline · seen \(Self.formattedTime(lastSeen))"
        }
    }

    func isDisabled(_ section: Section) -> Bool {
        disabledSectionIDs.contains(section.id)
    }

    /// Selects `section` and persists it via ``sectionStore`` (acceptance: "selection persists
    /// across launches").
    func select(_ section: Section) {
        selectedSectionID = section.id
        sectionStore.selectedSectionID = section.id
    }

    /// `HH:MM` in the current calendar/time zone (ui-spec §7.1: "Offline · seen 14:02"). Locked to
    /// `en_US_POSIX` so the 24-hour digits render the same regardless of the user's locale
    /// preference -- the time zone itself still tracks `.current`.
    static func formattedTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
