import Foundation

/// Presentation logic of the "Copied from <device>." toast shown when a clip arrives from the
/// phone. One toast at a time: a new clip replaces the text and restarts the hold timer. Never
/// carries clip content (invariant 7), only the sanitized device name.
@MainActor
public final class ClipboardToastViewModel {
    public static let fallbackDeviceName = "your phone"
    public static let holdDuration: Duration = .milliseconds(1800)

    private let clock: any Clock<Duration>
    private let deviceName: @MainActor () -> String?
    private let present: @MainActor (String?) -> Void
    private var hideTask: Task<Void, Never>?

    /// - Parameter present: called with the toast text to show, or `nil` to hide it.
    public init(
        clock: any Clock<Duration>,
        deviceName: @escaping @MainActor () -> String?,
        present: @escaping @MainActor (String?) -> Void
    ) {
        self.clock = clock
        self.deviceName = deviceName
        self.present = present
    }

    deinit {
        hideTask?.cancel()
    }

    public static func text(deviceName: String?) -> String {
        let name = deviceName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackDeviceName
        return "Copied from \(name)."
    }

    public func clipboardReceived() {
        hideTask?.cancel()
        present(Self.text(deviceName: deviceName()))
        let clock = clock
        hideTask = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.holdDuration)
            } catch {
                return
            }
            self?.present(nil)
        }
    }
}
