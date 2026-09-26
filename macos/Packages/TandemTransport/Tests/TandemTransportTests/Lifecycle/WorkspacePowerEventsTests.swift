import AppKit
import Foundation
import Testing
@testable import TandemTransport

/// E20-10: ``WorkspacePowerEvents``, the production ``SystemPowerEvents`` adapter, observed
/// against a plain injected `NotificationCenter` -- never the real `NSWorkspace.shared
/// .notificationCenter` -- so posting `NSWorkspace`'s own sleep/wake notification names is enough
/// to drive it deterministically in a unit test.
@Suite("WorkspacePowerEvents")
struct WorkspacePowerEventsTests {

    @Test
    func workspacePowerEvents_didWakeNotificationPosted_emitsDidWake() async {
        let notificationCenter = NotificationCenter()
        let powerEvents = WorkspacePowerEvents(notificationCenter: notificationCenter)
        var iterator = powerEvents.events.makeAsyncIterator()

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        let event = await iterator.next()
        #expect(event == .didWake)
    }
}
