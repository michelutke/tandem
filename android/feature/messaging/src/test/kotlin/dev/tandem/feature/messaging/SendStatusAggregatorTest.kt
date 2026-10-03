package dev.tandem.feature.messaging

import android.app.Activity
import android.telephony.SmsManager
import dev.tandem.protocol.v1.SendSmsErrorCode
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class SendStatusAggregatorTest {
    @Test
    fun sendStatusAggregator_allPartsResultOk_emitsSingleSentStatus() {
        val aggregator = SendStatusAggregator(partCount = 2)

        val updates =
            listOf(part(0, SendResultKind.SENT), part(1, SendResultKind.SENT), part(1, SendResultKind.SENT))
                .flatMap(aggregator::accept)

        assertEquals(listOf<SendUpdate>(SendUpdate.Sent), updates)
    }

    @Test
    fun sendStatusAggregator_secondPartNoService_emitsFailedNoService() {
        val aggregator = SendStatusAggregator(partCount = 2)

        val updates =
            listOf(
                part(0, SendResultKind.SENT),
                part(1, SendResultKind.SENT, SmsManager.RESULT_ERROR_NO_SERVICE),
                part(0, SendResultKind.DELIVERED),
            ).flatMap(aggregator::accept)

        assertEquals(
            listOf<SendUpdate>(
                SendUpdate.Failed(SendSmsErrorCode.SEND_SMS_ERROR_CODE_NO_SERVICE, SmsManager.RESULT_ERROR_NO_SERVICE),
            ),
            updates,
        )
    }

    @Test
    fun sendStatusAggregator_allDeliveryReportsOk_emitsDelivered() {
        val aggregator = SendStatusAggregator(partCount = 2)

        val updates =
            listOf(
                part(0, SendResultKind.SENT),
                part(1, SendResultKind.SENT),
                part(0, SendResultKind.DELIVERED),
                part(1, SendResultKind.DELIVERED),
            ).flatMap(aggregator::accept)

        assertEquals(listOf(SendUpdate.Sent, SendUpdate.Delivered), updates)
    }

    private fun part(
        index: Int,
        kind: SendResultKind,
        resultCode: Int = Activity.RESULT_OK,
    ) = PartResult("id-1", index, kind, resultCode)
}
