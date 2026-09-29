package dev.tandem.feature.notifications

/** Test fake (E30-04 tdd) standing in for [InstalledAppsSource] against the real `PackageManager`. */
class FakeInstalledAppsSource(
    private val apps: List<InstalledApp>,
) : InstalledAppsSource {
    override fun installedApps(): List<InstalledApp> = apps
}
