import os

struct Notification {
    let notificationText: String
}

func logNotification(_ notification: Notification) {
    os_log("%{public}@", notification.notificationText)
}
