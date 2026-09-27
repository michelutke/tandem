import ServiceManagement

/// The subset of `SMAppService.Status` this app distinguishes (backlog E22-03): mirrors it
/// one-for-one so ``LoginItemService`` conformers -- and the fakes that drive
/// ``LaunchAtLoginViewModel``'s tests -- never need to import `ServiceManagement`.
enum LoginItemStatus: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// Registers/unregisters this app as a login item and reports its current status. Seam over
/// `SMAppService` (backlog E22-03): ``SMAppServiceLoginItemService`` is the real implementation;
/// tests drive a scriptable fake instead.
///
/// `SMAppService` has no change notification -- callers are expected to re-read ``status()``
/// whenever the Settings window appears or the app becomes active (UC-01), not to cache it.
protocol LoginItemService {
    /// Registers this app to launch at login. Throws if the system call itself fails; never
    /// silently swallowed by conformers.
    func register() throws

    /// Unregisters this app from launching at login.
    func unregister() throws

    /// The login item's current status, read fresh from the system every call.
    func status() -> LoginItemStatus
}

/// The production ``LoginItemService``, over `SMAppService.mainApp`.
final class SMAppServiceLoginItemService: LoginItemService {
    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func status() -> LoginItemStatus {
        LoginItemStatus(SMAppService.mainApp.status)
    }
}

private extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}
