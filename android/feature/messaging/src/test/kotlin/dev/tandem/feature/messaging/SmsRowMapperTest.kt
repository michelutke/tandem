package dev.tandem.feature.messaging

import dev.tandem.protocol.v1.SmsMessageType
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class SmsRowMapperTest {
    @Test
    fun smsRowMapper_providerTypeCodes_mapToInboxSentOutboxFailedQueued() {
        val mapped = listOf(1, 2, 4, 5, 6).map { SmsRowMapper.messageType(it) }

        assertEquals(
            listOf(
                SmsMessageType.SMS_MESSAGE_TYPE_INBOX,
                SmsMessageType.SMS_MESSAGE_TYPE_SENT,
                SmsMessageType.SMS_MESSAGE_TYPE_OUTBOX,
                SmsMessageType.SMS_MESSAGE_TYPE_FAILED,
                SmsMessageType.SMS_MESSAGE_TYPE_QUEUED,
            ),
            mapped,
        )
    }

    @Test
    fun smsRowMapper_unknownProviderType_mapsToUnspecified() {
        assertEquals(SmsMessageType.SMS_MESSAGE_TYPE_UNSPECIFIED, SmsRowMapper.messageType(99))
    }

    @Test
    fun smsRowMapper_row_mapsAllFields() {
        val message = SmsRowMapper.toMessage(SmsRow(7, 3, "5551234", "hello", 1000, 1, 2))

        assertEquals(7L, message.id)
        assertEquals(3L, message.threadId)
        assertEquals("5551234", message.address)
        assertEquals("hello", message.body)
        assertEquals(1000L, message.timestampMs)
        assertEquals(SmsMessageType.SMS_MESSAGE_TYPE_INBOX, message.type)
        assertEquals(2, message.subscriptionId)
    }
}
