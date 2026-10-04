package dev.tandem.feature.mirror

import android.app.Activity
import android.os.Bundle

/** Test stand-in for the app's consent trampoline: the Start action reports the tap, then closes. */
class MirrorStartTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MirrorPromptActionDispatcher.controller?.onStartTapped()
        finish()
    }
}
