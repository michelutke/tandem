package dev.tandem.feature.clipboard

import dev.tandem.core.transport.TandemSession

/**
 * The Ready session the clipboard entry points (share target, process-text, capture activity)
 * send through (E20-23). Set by the connection orchestrator's clipboard feature while a session is
 * attached and cleared when it closes; the system constructs those activities, so they read it
 * through their `sessionProvider` defaults. Null means no live session: entry points do nothing.
 */
object LiveClipboardSession {
    @Volatile
    var current: TandemSession? = null

    /** Shared by the writer of received clips and the passive capture entry point (E31-08). */
    val loopGuard = ClipboardLoopGuard()
}
