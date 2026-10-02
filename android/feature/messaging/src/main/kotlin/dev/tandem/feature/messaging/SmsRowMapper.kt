package dev.tandem.feature.messaging

import android.provider.Telephony
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsMessageType
import dev.tandem.protocol.v1.smsMessage

data class SmsRow(
    val id: Long,
    val threadId: Long,
    val address: String,
    val body: String,
    val dateMs: Long,
    val providerType: Int,
    val subscriptionId: Int,
)

object SmsRowMapper {
    fun toMessage(row: SmsRow): SmsMessage =
        smsMessage {
            id = row.id
            threadId = row.threadId
            address = row.address
            body = row.body
            timestampMs = row.dateMs
            type = messageType(row.providerType)
            subscriptionId = row.subscriptionId
        }

    fun messageType(providerType: Int): SmsMessageType =
        when (providerType) {
            Telephony.Sms.MESSAGE_TYPE_INBOX -> SmsMessageType.SMS_MESSAGE_TYPE_INBOX
            Telephony.Sms.MESSAGE_TYPE_SENT -> SmsMessageType.SMS_MESSAGE_TYPE_SENT
            Telephony.Sms.MESSAGE_TYPE_DRAFT -> SmsMessageType.SMS_MESSAGE_TYPE_DRAFT
            Telephony.Sms.MESSAGE_TYPE_OUTBOX -> SmsMessageType.SMS_MESSAGE_TYPE_OUTBOX
            Telephony.Sms.MESSAGE_TYPE_FAILED -> SmsMessageType.SMS_MESSAGE_TYPE_FAILED
            Telephony.Sms.MESSAGE_TYPE_QUEUED -> SmsMessageType.SMS_MESSAGE_TYPE_QUEUED
            else -> SmsMessageType.SMS_MESSAGE_TYPE_UNSPECIFIED
        }
}
