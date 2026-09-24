# E00-17: release builds must never emit verbose/debug/info logcat output (invariant 7). R8
# treats these calls as no-ops and removes their call sites and (when unused) their arguments;
# Log.w/Log.e are kept for category-constant crash context.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
