package dev.tandem.feature.messaging

import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsMessageType
import dev.tandem.protocol.v1.SmsThread
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeSmsSource(
    var messages: List<SmsMessage> = emptyList(),
    var threads: List<SmsThread> = emptyList(),
    var readPermitted: Boolean = true,
) : SmsSource {
    private val changeEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    override fun threads(): List<SmsThread> = requirePermission().let { threads }

    override fun newerThan(
        sinceId: Long,
        limit: Int,
    ): List<SmsMessage> {
        requirePermission()
        return messages.filter { it.id > sinceId }.sortedBy { it.id }.take(limit)
    }

    override fun olderThan(
        beforeId: Long,
        limit: Int,
    ): List<SmsMessage> {
        requirePermission()
        return messages.filter { it.id < beforeId }.sortedByDescending { it.id }.take(limit)
    }

    override fun maxId(): Long {
        requirePermission()
        return messages.maxOfOrNull { it.id } ?: 0
    }

    override fun newestOutgoingId(
        address: String,
        afterId: Long,
    ): Long {
        requirePermission()
        return messages
            .filter { it.address == address && it.id > afterId && it.type in OUTGOING_TYPES }
            .maxOfOrNull { it.id } ?: 0
    }

    override fun changes(): Flow<Unit> = changeEvents

    private fun requirePermission() {
        if (!readPermitted) throw SmsPermissionMissing()
    }

    fun emitChange() {
        changeEvents.tryEmit(Unit)
    }

    private companion object {
        val OUTGOING_TYPES = setOf(SmsMessageType.SMS_MESSAGE_TYPE_SENT, SmsMessageType.SMS_MESSAGE_TYPE_OUTBOX)
    }
}
