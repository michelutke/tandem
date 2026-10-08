package dev.tandem.feature.files

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Aggregate bytes of every in-flight transfer in each direction, for the Home ring. Bytes only:
 * file names never leave the transfer layer. A direction with no transfer is null.
 */
data class TransferActivity(
    val sending: TransferBytes? = null,
    val receiving: TransferBytes? = null,
) {
    val isActive: Boolean get() = sending != null || receiving != null
}

/**
 * Turns the in-flight byte maps of the sender and receiver into [TransferActivity] for one batch:
 * a transfer that leaves its map counts as fully done until every transfer of that direction has
 * finished, so the aggregate never goes backwards. An empty direction starts a new batch.
 */
class TransferBatchAggregator {
    private class Direction {
        var finished = 0L
        var last = emptyMap<String, TransferBytes>()

        fun update(current: Map<String, TransferBytes>): TransferBytes? {
            if (current.isEmpty()) {
                finished = 0
                last = emptyMap()
                return null
            }
            last.filterKeys { it !in current }.values.forEach { finished += it.total }
            last = current
            val total = current.values.sumOf { it.total }
            return TransferBytes(finished + current.values.sumOf { it.transferred }, finished + total)
        }
    }

    private val sending = Direction()
    private val receiving = Direction()

    @Synchronized
    fun update(
        sent: Map<String, TransferBytes>,
        received: Map<String, TransferBytes>,
    ) = TransferActivity(sending.update(sent), receiving.update(received))
}

/** Process-wide view of the current session's transfers, published by the files feature while attached. */
object LiveTransferActivity {
    private val mutableState = MutableStateFlow(TransferActivity())
    val state: StateFlow<TransferActivity> = mutableState.asStateFlow()

    fun publish(activity: TransferActivity) {
        mutableState.value = activity
    }
}
