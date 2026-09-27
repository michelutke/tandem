package dev.tandem.companion

/**
 * E00-22: wire contract for the companion notification-poster app. Kept in one file so the
 * `dev.tandem.companion.POST` broadcast action, its extras, and the record `ContentProvider`'s
 * URIs/columns stay in sync between [CompanionReceiver]/[ActionReceiver], [RecordsProvider], and
 * every caller (`adb shell am broadcast`, an instrumented test's own explicit broadcast).
 */
object CompanionContract {
    const val ACTION_POST = "dev.tandem.companion.POST"
    const val ACTION_FIRED = "dev.tandem.companion.ACTION_FIRED"

    const val EXTRA_KIND = "kind"
    const val EXTRA_KEY = "key"
    const val EXTRA_TEXT = "text"
    const val EXTRA_SENDERS = "senders"
    const val EXTRA_COUNT = "count"
    const val EXTRA_INTERVAL_MS = "intervalMs"
    const val EXTRA_NONCE = "nonce"
    const val EXTRA_ACTION_ID = "actionId"

    const val KIND_PLAIN = "plain"
    const val KIND_BIG_TEXT = "bigText"
    const val KIND_MESSAGING_GROUP = "messagingGroup"
    const val KIND_ACTIONS = "actions"
    const val KIND_SECRET = "secret"
    const val KIND_PRIVATE = "private"
    const val KIND_ONGOING = "ongoing"
    const val KIND_BURST = "burst"
    const val KIND_CANARY = "canary"
    const val KIND_CANCEL = "cancel"

    const val ACTION_ID_ACK = "ack"
    const val ACTION_ID_REPLY = "reply"
    const val REMOTE_INPUT_KEY = "reply_text"

    const val AUTHORITY = "dev.tandem.companion.records"
    const val PATH_ACTIONS = "actions"
    const val PATH_REPLIES = "replies"

    const val COLUMN_KEY = "key"
    const val COLUMN_ACTION_ID = "action_id"
    const val COLUMN_TEXT = "text"

    const val CHANNEL_ID = "dev.tandem.companion.default"
    const val NOTIFICATION_ID = 1
    const val DEFAULT_KEY = "default"
    const val CANARY_PREFIX = "TANDEM-CANARY-"
}
