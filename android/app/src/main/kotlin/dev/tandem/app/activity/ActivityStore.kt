package dev.tandem.app.activity

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.PeerDataPurging
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Clock
import java.time.Duration
import java.time.Instant

/**
 * Local metadata-only Activity feed (E20-18; invariant 7). Entries older than [RETENTION] are
 * dropped by [purgeExpired]; unpair clears the feed through [PeerDataPurging].
 */
class ActivityStore(
    private val dataStore: DataStore<Preferences>,
    private val clock: Clock,
) : PeerDataPurging {
    val entries: Flow<List<ActivityEntry>> = dataStore.data.map { decode(it[ENTRIES_KEY]) }

    suspend fun record(entry: ActivityEntry) {
        dataStore.edit { it[ENTRIES_KEY] = encode(decode(it[ENTRIES_KEY]) + entry) }
    }

    suspend fun purgeExpired() {
        val cutoff = clock.instant().minus(RETENTION)
        dataStore.edit { preferences ->
            preferences[ENTRIES_KEY] = encode(decode(preferences[ENTRIES_KEY]).filter { it.timestamp >= cutoff })
        }
    }

    suspend fun clear() {
        dataStore.edit { it.remove(ENTRIES_KEY) }
    }

    override suspend fun purgeAll(peerFingerprint: SpkiFingerprint) = clear()

    private fun encode(entries: List<ActivityEntry>): String =
        entries.joinToString("\n") {
            listOf(it.type.name, it.sizeBytes ?: NONE, it.durationSeconds ?: NONE, it.timestamp.toEpochMilli())
                .joinToString(SEPARATOR)
        }

    private fun decode(raw: String?): List<ActivityEntry> =
        raw
            .orEmpty()
            .lineSequence()
            .filter { it.isNotBlank() }
            .mapNotNull(::decodeLine)
            .toList()

    private fun decodeLine(line: String): ActivityEntry? {
        val parts = line.split(SEPARATOR)
        val type = ActivityEventType.entries.firstOrNull { it.name == parts.getOrNull(0) }
        val epochMillis = parts.getOrNull(TIMESTAMP_INDEX)?.toLongOrNull()
        return if (type == null || epochMillis == null) {
            null
        } else {
            ActivityEntry(
                type = type,
                sizeBytes = parts[SIZE_INDEX].toLongOrNull(),
                durationSeconds = parts[DURATION_INDEX].toLongOrNull(),
                timestamp = Instant.ofEpochMilli(epochMillis),
            )
        }
    }

    companion object {
        val RETENTION: Duration = Duration.ofDays(7)
        private val ENTRIES_KEY = stringPreferencesKey("activity_entries")
        private const val SEPARATOR = ","
        private const val NONE = "-"
        private const val SIZE_INDEX = 1
        private const val DURATION_INDEX = 2
        private const val TIMESTAMP_INDEX = 3
    }
}
