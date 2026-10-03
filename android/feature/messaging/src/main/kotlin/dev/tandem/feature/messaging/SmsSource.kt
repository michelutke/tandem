package dev.tandem.feature.messaging

import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsThread
import kotlinx.coroutines.flow.Flow

/** READ_SMS is not granted; thrown instead of a raw [SecurityException]. */
class SmsPermissionMissing : Exception("READ_SMS not granted")

/**
 * E50-02 feature-local seam over the phone's SMS provider: sync reads SMS only through this
 * interface, so tests script it with `FakeSmsSource` instead of a real provider. Every read
 * throws [SmsPermissionMissing] when READ_SMS is not granted.
 */
interface SmsSource {
    /** Up to [PAGE_SIZE] conversations, newest first. */
    fun threads(): List<SmsThread>

    /** Up to [limit] messages with an id greater than [sinceId], ascending by id. */
    fun newerThan(
        sinceId: Long,
        limit: Int = PAGE_SIZE,
    ): List<SmsMessage>

    /** Up to [limit] messages with an id less than [beforeId], descending by id. */
    fun olderThan(
        beforeId: Long,
        limit: Int = PAGE_SIZE,
    ): List<SmsMessage>

    /** Highest SMS id in the provider, or 0 when empty. */
    fun maxId(): Long

    /** Id of the newest SENT/OUTBOX row for [address] with an id greater than [afterId], or 0 when none. */
    fun newestOutgoingId(
        address: String,
        afterId: Long,
    ): Long

    /** Emits once per provider change notification on the SMS store. */
    fun changes(): Flow<Unit>

    companion object {
        const val PAGE_SIZE = 200
    }
}
