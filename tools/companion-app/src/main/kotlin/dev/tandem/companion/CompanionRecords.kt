package dev.tandem.companion

import java.util.concurrent.CopyOnWriteArrayList

/**
 * E00-22: in-memory records of every action fired and every RemoteInput reply received, read
 * back through [RecordsProvider]. Companion-app process only; never shipped.
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

    val actionsFired = CopyOnWriteArrayList<ActionFired>()
    val repliesReceived = CopyOnWriteArrayList<ReplyReceived>()
}
