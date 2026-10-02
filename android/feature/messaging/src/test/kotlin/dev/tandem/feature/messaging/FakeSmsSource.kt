package dev.tandem.feature.messaging

import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsThread
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeSmsSource(
    var messages: List<SmsMessage> = emptyList(),
    var threads: List<SmsThread> = emptyList(),
) : SmsSource {
    private val changeEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    override fun threads(): List<SmsThread> = threads

    override fun newerThan(
        sinceId: Long,
        limit: Int,
    ): List<SmsMessage> = messages.filter { it.id > sinceId }.sortedBy { it.id }.take(limit)

    override fun olderThan(
        beforeId: Long,
        limit: Int,
    ): List<SmsMessage> = messages.filter { it.id < beforeId }.sortedByDescending { it.id }.take(limit)

    override fun maxId(): Long = messages.maxOfOrNull { it.id } ?: 0

    override fun changes(): Flow<Unit> = changeEvents

    fun emitChange() {
        changeEvents.tryEmit(Unit)
    }
}
