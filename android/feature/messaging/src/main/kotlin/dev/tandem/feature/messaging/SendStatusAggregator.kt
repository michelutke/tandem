package dev.tandem.feature.messaging

import android.app.Activity
import dev.tandem.protocol.v1.SendSmsErrorCode

/** What [SendStatusAggregator] tells the caller to report. */
sealed interface SendUpdate {
    data object Sent : SendUpdate

    data object Delivered : SendUpdate

    data class Failed(
        val errorCode: SendSmsErrorCode,
        val resultCode: Int,
    ) : SendUpdate
}

/**
 * Pure per-send state: folds per-part sent/delivery results into at most one [SendUpdate.Sent],
 * then either one [SendUpdate.Delivered] or one [SendUpdate.Failed] (never both a failure and a
 * success). [finished] once nothing more will be emitted.
 */
class SendStatusAggregator(
    private val partCount: Int,
) {
    private val sentParts = mutableSetOf<Int>()
    private val deliveredParts = mutableSetOf<Int>()
    private var sentEmitted = false
    var finished = false
        private set

    fun accept(result: PartResult): List<SendUpdate> {
        if (finished || result.partIndex !in 0 until partCount) return emptyList()
        return if (result.resultCode == Activity.RESULT_OK) record(result) else listOf(fail(result.resultCode))
    }

    private fun record(result: PartResult): List<SendUpdate> {
        val updates = mutableListOf<SendUpdate>()
        when (result.kind) {
            SendResultKind.SENT -> sentParts += result.partIndex
            SendResultKind.DELIVERED -> deliveredParts += result.partIndex
        }
        if (!sentEmitted && sentParts.size == partCount) {
            sentEmitted = true
            updates += SendUpdate.Sent
        }
        if (sentEmitted && deliveredParts.size == partCount) {
            finished = true
            updates += SendUpdate.Delivered
        }
        return updates
    }

    private fun fail(resultCode: Int): SendUpdate {
        finished = true
        return SendUpdate.Failed(SendResultMapper.errorCode(resultCode), resultCode)
    }
}
