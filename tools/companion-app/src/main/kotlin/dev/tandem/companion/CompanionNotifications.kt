package dev.tandem.companion

import android.app.Notification
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon

/**
 * E00-22: builds the [Notification.Builder]/[Notification.Action] for every `kind` on
 * `dev.tandem.companion.POST`, kept out of [CompanionReceiver] itself to stay under detekt's
 * per-class function-count threshold.
 */
internal object CompanionNotifications {
    fun plain(
        context: Context,
        intent: Intent,
    ): Notification.Builder =
        Notification
            .Builder(context, CompanionContract.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Companion")
            .setContentText(intent.getStringExtra(CompanionContract.EXTRA_TEXT) ?: "")

    fun bigText(
        context: Context,
        intent: Intent,
    ): Notification.Builder {
        val text = intent.getStringExtra(CompanionContract.EXTRA_TEXT) ?: ""
        return plain(context, intent).setStyle(Notification.BigTextStyle().bigText(text))
    }

    fun messagingGroup(
        context: Context,
        intent: Intent,
    ): Notification.Builder {
        val senders = intent.getIntExtra(CompanionContract.EXTRA_SENDERS, 1)
        val me = Person.Builder().setName("Me").build()
        val style = Notification.MessagingStyle(me).setGroupConversation(true).setConversationTitle("Companion group")
        for (index in 0 until senders) {
            val sender = Person.Builder().setName("Sender $index").build()
            style.addMessage("Message $index", index.toLong(), sender)
        }
        return Notification
            .Builder(context, CompanionContract.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setStyle(style)
    }

    fun actions(
        context: Context,
        key: String,
    ): Notification.Builder {
        val ackAction =
            Notification.Action
                .Builder(
                    Icon.createWithResource(context, android.R.drawable.ic_menu_send),
                    "Ack",
                    PendingIntent.getBroadcast(
                        context,
                        key.hashCode() * 2,
                        Intent(context, ActionReceiver::class.java)
                            .setAction(CompanionContract.ACTION_FIRED)
                            .putExtra(CompanionContract.EXTRA_KEY, key)
                            .putExtra(CompanionContract.EXTRA_ACTION_ID, CompanionContract.ACTION_ID_ACK),
                        PendingIntent.FLAG_IMMUTABLE,
                    ),
                ).build()

        return Notification
            .Builder(context, CompanionContract.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Companion")
            .setContentText("actions")
            .addAction(ackAction)
            .addAction(buildReplyAction(context, key))
    }

    fun canary(
        context: Context,
        intent: Intent,
    ): Notification.Builder {
        val nonce = intent.getStringExtra(CompanionContract.EXTRA_NONCE) ?: ""
        return Notification
            .Builder(context, CompanionContract.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Companion")
            .setContentText("${CompanionContract.CANARY_PREFIX}$nonce")
    }

    // E00-22: RemoteInput direct-reply requires a mutable PendingIntent so the system can attach
    // the typed reply text to the Intent it fires (see
    // tools/lint/pending-intent-mutable.allowlist).
    private fun buildReplyAction(
        context: Context,
        key: String,
    ): Notification.Action {
        val remoteInput = RemoteInput.Builder(CompanionContract.REMOTE_INPUT_KEY).setLabel("Reply").build()
        val replyIntent =
            PendingIntent.getBroadcast(
                context,
                key.hashCode() * 2 + 1,
                Intent(context, ActionReceiver::class.java)
                    .setAction(CompanionContract.ACTION_FIRED)
                    .putExtra(CompanionContract.EXTRA_KEY, key)
                    .putExtra(CompanionContract.EXTRA_ACTION_ID, CompanionContract.ACTION_ID_REPLY),
                PendingIntent.FLAG_MUTABLE,
            )
        return Notification.Action
            .Builder(
                Icon.createWithResource(context, android.R.drawable.ic_menu_send),
                "Reply",
                replyIntent,
            ).addRemoteInput(remoteInput)
            .build()
    }
}
