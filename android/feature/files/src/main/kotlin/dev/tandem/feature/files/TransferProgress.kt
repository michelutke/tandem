package dev.tandem.feature.files

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Clock

/** Bytes moved so far of [total] for one in-flight transfer. */
data class TransferBytes(
    val transferred: Long,
    val total: Long,
)

data class TransferProgress(
    val percent: Int,
    val bytesPerSecond: Long,
)

/**
 * Maps [source] (the byte counters of [FileSender] / [FileReceiver]) to [TransferProgress] per
 * transfer id (E40-12): re-evaluated every [EMIT_INTERVAL_MILLIS], speed averaged over the trailing
 * [SPEED_WINDOW_MILLIS]. A transfer that leaves [source] leaves [progress].
 */
class TransferProgressViewModel(
    private val source: StateFlow<Map<String, TransferBytes>>,
    private val clock: Clock,
    scope: CoroutineScope,
) {
    private val samples = HashMap<String, ArrayDeque<Sample>>()
    private val state = MutableStateFlow<Map<String, TransferProgress>>(emptyMap())

    val progress: StateFlow<Map<String, TransferProgress>> = state.asStateFlow()

    init {
        scope.launch {
            while (true) {
                delay(EMIT_INTERVAL_MILLIS)
                tick()
            }
        }
    }

    private fun tick() {
        val now = clock.millis()
        val current = source.value
        samples.keys.retainAll(current.keys)
        state.value =
            current.mapValues { (id, bytes) ->
                val window = samples.getOrPut(id) { ArrayDeque() }
                window.addLast(Sample(now, bytes.transferred))
                while (window.first().atMillis < now - SPEED_WINDOW_MILLIS) window.removeFirst()
                TransferProgress(percent(bytes), speed(window))
            }
    }

    private fun percent(bytes: TransferBytes): Int =
        if (bytes.total <=
            0
        ) {
            0
        } else {
            (bytes.transferred * PERCENT_SCALE / bytes.total).toInt().coerceIn(0, PERCENT_SCALE)
        }

    private fun speed(window: ArrayDeque<Sample>): Long {
        val elapsed = window.last().atMillis - window.first().atMillis
        if (elapsed <= 0) return 0
        return (window.last().bytes - window.first().bytes) * MILLIS_PER_SECOND / elapsed
    }

    private class Sample(
        val atMillis: Long,
        val bytes: Long,
    )

    private companion object {
        const val EMIT_INTERVAL_MILLIS = 250L
        const val SPEED_WINDOW_MILLIS = 3_000L
        const val MILLIS_PER_SECOND = 1_000L
        const val PERCENT_SCALE = 100
    }
}
