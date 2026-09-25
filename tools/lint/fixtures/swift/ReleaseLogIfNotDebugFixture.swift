import os

func logSecret(_ secret: String) {
    #if !DEBUG
    os_log("%@", secret)
    #endif
}
