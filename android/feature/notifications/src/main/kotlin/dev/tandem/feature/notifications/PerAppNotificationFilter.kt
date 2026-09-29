package dev.tandem.feature.notifications

import android.service.notification.StatusBarNotification
import androidx.datastore.preferences.core.stringSetPreferencesKey
import dev.tandem.core.storage.settings.SettingsKey
import dev.tandem.core.storage.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/** A user-set per-app override (E30-04), on top of [NotificationFilter]'s default rules. */
enum class FilterOverride {
    ALLOW,
    DENY,
}

/** One row on [PerAppNotificationFilterScreen]: an installed app plus its current toggle state. */
data class PerAppFilterRow(
    val packageName: String,
    val label: String,
    val allowed: Boolean,
)

/**
 * E30-04: per-app allow/deny overrides on top of [NotificationFilter]'s default rules, persisted
 * in [settingsStore] (DataStore, E13-04) so a [DENY] or [ALLOW] survives an app restart. The
 * allow/deny list is managed on the phone only (backlog notes: Android owns the notification-access
 * permission and the authoritative installed-app list).
 *
 * [deniedPackages]/[allowedPackages] are [StateFlow]s eagerly collected in [scope] rather than a
 * value read once at construction, so [shouldForward] always sees the latest DataStore write --
 * UC-11's "a toggle applies to the next notification without a session reconnect" requirement.
 * A package in both sets is unreachable: [setOverride] always removes the opposite set's entry
 * before/with adding to the requested one.
 */
class PerAppNotificationFilter(
    private val settingsStore: SettingsStore,
    scope: CoroutineScope,
) {
    private val deniedPackages: StateFlow<Set<String>> =
        settingsStore
            .get(DENIED_PACKAGES_KEY)
            .stateIn(scope, SharingStarted.Eagerly, DENIED_PACKAGES_KEY.default)
    private val allowedPackages: StateFlow<Set<String>> =
        settingsStore
            .get(ALLOWED_PACKAGES_KEY)
            .stateIn(scope, SharingStarted.Eagerly, ALLOWED_PACKAGES_KEY.default)

    fun shouldForward(
        sbn: StatusBarNotification,
        ownPackageName: String,
    ): Boolean =
        when {
            sbn.packageName in deniedPackages.value -> false
            sbn.packageName in allowedPackages.value -> true
            else -> NotificationFilter.shouldForward(sbn, ownPackageName)
        }

    /** Whether [packageName] is currently allowed, for the settings screen's toggle state --
     * [override] if set, otherwise [NotificationFilter]'s default (system-noise packages start
     * off, everything else starts on). */
    fun isAllowed(packageName: String): Boolean =
        when {
            packageName in deniedPackages.value -> false
            packageName in allowedPackages.value -> true
            else -> !NotificationFilter.isSystemNoisePackage(packageName)
        }

    /** Sets or clears [packageName]'s override. `null` reverts to [NotificationFilter]'s default. */
    suspend fun setOverride(
        packageName: String,
        override: FilterOverride?,
    ) {
        val nextDenied = deniedPackages.value.withOverride(packageName, apply = override == FilterOverride.DENY)
        val nextAllowed = allowedPackages.value.withOverride(packageName, apply = override == FilterOverride.ALLOW)
        settingsStore.set(DENIED_PACKAGES_KEY, nextDenied)
        settingsStore.set(ALLOWED_PACKAGES_KEY, nextAllowed)
    }

    /** Maps [installedApps] (from [InstalledAppsSource]) to [PerAppNotificationFilterScreen] rows,
     * each with this filter's current [isAllowed] state for that app. */
    fun rowsFor(installedApps: List<InstalledApp>): List<PerAppFilterRow> =
        installedApps.map { app -> PerAppFilterRow(app.packageName, app.label, isAllowed(app.packageName)) }

    private fun Set<String>.withOverride(
        packageName: String,
        apply: Boolean,
    ): Set<String> = if (apply) this + packageName else this - packageName

    companion object {
        val DENIED_PACKAGES_KEY = SettingsKey(stringSetPreferencesKey("per_app_denied_packages"), emptySet())
        val ALLOWED_PACKAGES_KEY = SettingsKey(stringSetPreferencesKey("per_app_allowed_packages"), emptySet())
    }
}
