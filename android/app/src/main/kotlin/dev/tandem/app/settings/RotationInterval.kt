package dev.tandem.app.settings

import androidx.datastore.preferences.core.intPreferencesKey
import dev.tandem.core.storage.settings.SettingsKey
import java.time.Duration

/** Q18 applied default: rotate 365 days after the last rotation (or pairing); 0 is Off, 90/180/365 are the options. */
const val DEFAULT_ROTATION_INTERVAL_DAYS = 365

val ROTATION_INTERVAL_DAYS_KEY =
    SettingsKey(intPreferencesKey("rotation_interval_days"), DEFAULT_ROTATION_INTERVAL_DAYS)

/** The scheduler interval for a persisted [days] value; null when scheduled rotation is Off. */
fun rotationInterval(days: Int): Duration? = days.takeIf { it > 0 }?.let { Duration.ofDays(it.toLong()) }
