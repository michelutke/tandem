package dev.tandem.companion

import android.content.Context

/**
 * E00-22: records of every action fired and every RemoteInput reply received, read back through
 * [RecordsProvider]. Persisted to [android.content.SharedPreferences] rather than kept in
 * memory: [ActionReceiver] runs as a plain (non-`goAsync`) manifest broadcast receiver, so the
 * system is free to kill the companion-app process as soon as `onReceive` returns, before a
 * later query against [RecordsProvider] — which may run in a fresh process — ever sees an
 * in-memory record. Never shipped; companion app only.
 */
object CompanionRecords {
    data class ActionFired(
        val key: String,
        val actionId: String,
    )

    data class ReplyReceived(
        val key: String,
        val text: String,
    )

    fun recordActionFired(
        context: Context,
        key: String,
        actionId: String,
    ) {
        appendEntry(context, KEY_ACTIONS_FIRED, key, actionId)
    }

    fun recordReplyReceived(
        context: Context,
        key: String,
        text: String,
    ) {
        appendEntry(context, KEY_REPLIES_RECEIVED, key, text)
    }

    fun actionsFired(context: Context): List<ActionFired> =
        readEntries(context, KEY_ACTIONS_FIRED) { key, value -> ActionFired(key, value) }

    fun repliesReceived(context: Context): List<ReplyReceived> =
        readEntries(context, KEY_REPLIES_RECEIVED) { key, value -> ReplyReceived(key, value) }

    private fun appendEntry(
        context: Context,
        prefsKey: String,
        key: String,
        value: String,
    ) {
        val prefs = prefs(context)
        val entry = "$key$FIELD_SEPARATOR$value"
        val existing = prefs.getString(prefsKey, "") ?: ""
        val updated = if (existing.isEmpty()) entry else "$existing$ENTRY_SEPARATOR$entry"
        // commit(), not apply(): ActionReceiver is a plain (non-goAsync) broadcast receiver, so
        // the system can kill this process the instant onReceive returns. apply()'s async write
        // could still be pending when that happens and never reach disk.
        prefs.edit().putString(prefsKey, updated).commit()
    }

    private fun <T> readEntries(
        context: Context,
        prefsKey: String,
        toRecord: (key: String, value: String) -> T,
    ): List<T> {
        val existing = prefs(context).getString(prefsKey, "") ?: ""
        if (existing.isEmpty()) return emptyList()
        return existing.split(ENTRY_SEPARATOR).map { entry ->
            val (key, value) = entry.split(FIELD_SEPARATOR, limit = 2)
            toRecord(key, value)
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private const val PREFS_NAME = "dev.tandem.companion.records"
    private const val KEY_ACTIONS_FIRED = "actionsFired"
    private const val KEY_REPLIES_RECEIVED = "repliesReceived"
    private const val FIELD_SEPARATOR = "\u0001"
    private const val ENTRY_SEPARATOR = "\u0002"
}
