import CoreFoundation
import Foundation

/// Payload-free Darwin notification the Share extension posts after enqueueing; the agent then
/// drains the queue. There is no XPC service and no data crosses this channel.
public enum SendRequestWake {
    static let notificationName = "dev.tandem.send-request-queue.wake"

    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

public final class SendRequestWakeObserver: @unchecked Sendable {
    private let handler: @Sendable () -> Void

    public init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<SendRequestWakeObserver>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            SendRequestWake.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(SendRequestWake.notificationName as CFString),
            nil
        )
    }
}
