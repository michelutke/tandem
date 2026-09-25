import os

struct Notification {
    let notificationText: String
}

func logNotification(_ notification: Notification) {
    #if DEBUG
    os_log("%{public}@", notification.notificationText)
    #endif
}
