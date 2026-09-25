import os

func redacted(_ value: String) -> String {
    String(repeating: "*", count: value.count)
}

func logClipboard(_ clipboardText: String) {
    os_log("clip len=%d", clipboardText.count)
    os_log("clip=%@", redacted(clipboardText))
}
