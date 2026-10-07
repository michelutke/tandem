package dev.tandem.app.activity

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.Clock

/** Records Activity feed rows (E20-18) from synchronous callbacks; metadata only, never content (invariant 7). */
class ActivityRecorder(
    private val store: ActivityStore,
    private val scope: CoroutineScope,
    private val clock: Clock,
) {
    fun record(
        type: ActivityEventType,
        sizeBytes: Long? = null,
        durationSeconds: Long? = null,
    ) {
        val entry = ActivityEntry(type, sizeBytes, durationSeconds, clock.instant())
        scope.launch { store.record(entry) }
    }
}
