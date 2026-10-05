# E00-17: release builds must never emit verbose/debug/info logcat output (invariant 7). R8
# treats these calls as no-ops and removes their call sites and (when unused) their arguments;
# Log.w/Log.e are kept for category-constant crash context.
-assumenosideeffects class android.util.Log {
    public static int v(...) return 0;
    public static int d(...) return 0;
    public static int i(...) return 0;
}
# `return 0` also strips call sites whose result is consumed (e.g. an expression-bodied lambda in a
# dependency such as camera-pipe returning Log.d's int).
