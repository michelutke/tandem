package dev.tandem.feature.notifications

import android.content.Context
import android.content.Intent

/** One installed app, as listed on the per-app notification filter screen (E30-04). */
data class InstalledApp(
    val packageName: String,
    val label: String,
)

/**
 * Seam over `PackageManager` (E30-04): the per-app notification filter screen's app list, so its
 * view model stays plain unit-tested against a fake instead of touching the framework directly
 * (CLAUDE.md's Robolectric rule; same idiom as `app/onboarding`'s `BatteryOptimizationSource`).
 * [SystemInstalledAppsSource] is the only production implementation.
 */
fun interface InstalledAppsSource {
    fun installedApps(): List<InstalledApp>
}

/**
 * Production implementation backed by the real `PackageManager`, scoped to apps with a launcher
 * entry (this module's manifest declares a matching `<queries>` element) rather than every
 * installed package -- Android 11+'s package-visibility rules block an unscoped
 * `getInstalledApplications` query, and a launcher entry is what makes an app relevant to a
 * user-facing notification filter anyway.
 */
class SystemInstalledAppsSource(
    private val context: Context,
) : InstalledAppsSource {
    // ImplicitInternalIntent: a query-only Intent (queryIntentActivities), never sent -- there is
    // no internal target to set (rule's own kdoc: a genuinely external implicit Intent).
    @Suppress("ImplicitInternalIntent")
    override fun installedApps(): List<InstalledApp> {
        val packageManager = context.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager
            .queryIntentActivities(launcherIntent, 0)
            .map { resolveInfo ->
                InstalledApp(
                    resolveInfo.activityInfo.packageName,
                    resolveInfo.loadLabel(packageManager).toString(),
                )
            }.distinctBy { it.packageName }
    }
}
