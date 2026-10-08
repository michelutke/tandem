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

    companion object {
        fun of(
            sending: Map<String, TransferBytes>,
            receiving: Map<String, TransferBytes>,
        ) = TransferActivity(sending.aggregate(), receiving.aggregate())

        private fun Map<String, TransferBytes>.aggregate(): TransferBytes? =
            takeIf { isNotEmpty() }?.values?.let { all ->
                TransferBytes(all.sumOf { it.transferred }, all.sumOf { it.total })
            }
    }
}

/** Process-wide view of the current session's transfers, published by the files feature while attached. */
object LiveTransferActivity {
    private val mutableState = MutableStateFlow(TransferActivity())
    val state: StateFlow<TransferActivity> = mutableState.asStateFlow()

    fun publish(activity: TransferActivity) {
        mutableState.value = activity
    }
}
