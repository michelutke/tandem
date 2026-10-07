package dev.tandem.feature.clipboard

import android.view.accessibility.AccessibilityEvent
import dev.tandem.core.transport.time.ElapsedRealtimeSource

/**
 * Stateful copy detection on top of [CopyEventFilter] (ADR-007). On Pixel builds the System UI
 * text-selection toolbar reports its action labels ("Kopieren", "Ausschneiden", ...) and the copy
 * overlay itself reports no text, so a copy is: the toolbar offered Copy or Cut, then an empty
 * System UI window-state event follows within [windowMillis]. A spurious match only re-reads an
 * unchanged clip, which the capture activity skips.
 */
class CopyDetector(
    private val clock: ElapsedRealtimeSource,
    private val windowMillis: Long = DEFAULT_WINDOW_MILLIS,
) {
    private var copyOfferedAt: Long? = null

    @Suppress("LongParameterList")
    @Synchronized
    fun onEvent(
        packageName: CharSequence?,
        eventType: Int,
        className: CharSequence?,
        texts: List<CharSequence>,
        localizedMarkers: List<String>,
        copyActionLabels: List<String>,
    ): Boolean {
        val isOverlay = CopyEventFilter.isCopyOverlay(packageName, eventType, className, texts, localizedMarkers)
        val isSystemUiWindow =
            packageName?.toString() == CopyEventFilter.SYSTEM_UI_PACKAGE &&
                eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        val now = clock.elapsedRealtimeMillis()
        val offersCopy = texts.any { text -> copyActionLabels.any { text.toString().equals(it, ignoreCase = true) } }
        val followsCopyOffer = copyOfferedAt?.let { texts.isEmpty() && now - it <= windowMillis } == true
        val isCopy = isOverlay || (isSystemUiWindow && !offersCopy && followsCopyOffer)
        copyOfferedAt =
            when {
                isCopy -> null
                isSystemUiWindow && offersCopy -> now
                else -> copyOfferedAt
            }
        return isCopy
    }

    companion object {
        const val DEFAULT_WINDOW_MILLIS = 5_000L
    }
}
