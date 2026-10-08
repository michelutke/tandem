package dev.tandem.app.home

import dev.tandem.feature.files.TransferActivity
import dev.tandem.feature.files.TransferBytes
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Lets a running file transfer, in either direction, take over [idle]'s ring with aggregate
 * progress (ui-spec §6), then shows [HomeRingState.TransferDone] for [doneMillis] before the ring
 * returns to [idle]. A transfer starting during that pause replaces it at once.
 */
class TransferHomeRingStateSource(
    private val idle: HomeRingStateSource,
    activity: Flow<TransferActivity>,
    scope: CoroutineScope,
    private val doneMillis: Long = DEFAULT_DONE_MILLIS,
) : HomeRingStateSource {
    private val overlay = MutableStateFlow<HomeRingState?>(null)
    private var doneTimer: Job? = null

    override val state: StateFlow<HomeRingState> =
        combine(idle.state, overlay) { base, task -> task ?: base }
            .stateIn(scope, SharingStarted.Eagerly, idle.state.value)

    init {
        scope.launch {
            var lastToMac = true
            var wasActive = false
            activity.collect { current ->
                val shown = current.toRingState()
                if (shown != null) {
                    doneTimer?.cancel()
                    wasActive = true
                    lastToMac = shown.toMac
                    overlay.value = shown
                } else if (wasActive) {
                    wasActive = false
                    overlay.value = HomeRingState.TransferDone(lastToMac)
                    doneTimer =
                        scope.launch {
                            delay(doneMillis)
                            overlay.value = null
                        }
                }
            }
        }
    }

    private fun TransferActivity.toRingState(): HomeRingState.Transfer? {
        val out = sending
        val inbound = receiving
        return when {
            out != null -> HomeRingState.Transfer(out.percent(), toMac = true)
            inbound != null -> HomeRingState.Transfer(inbound.percent(), toMac = false)
            else -> null
        }
    }

    private fun TransferBytes.percent(): Int =
        if (total <= 0) 0 else (transferred * PERCENT / total).toInt().coerceIn(0, PERCENT.toInt())

    private companion object {
        const val DEFAULT_DONE_MILLIS = 1_500L
        const val PERCENT = 100L
    }
}
