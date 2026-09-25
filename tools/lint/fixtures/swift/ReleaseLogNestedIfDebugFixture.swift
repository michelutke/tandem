import os

func logSecret(_ secret: String) {
    #if os(macOS)
    #if DEBUG
    os_log("%@", secret)
    #else
    os_log("%@", secret)
    #endif
    #endif
}
