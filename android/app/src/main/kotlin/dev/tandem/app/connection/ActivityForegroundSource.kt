package dev.tandem.app.connection

import android.app.Activity
import android.app.Application
import android.os.Bundle
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/** Emits when the app comes to the foreground: its first activity starts after none was started. */
class ActivityForegroundSource(
    private val application: Application,
) {
    val foregrounded: Flow<Unit> =
        callbackFlow {
            val callbacks =
                object : Application.ActivityLifecycleCallbacks {
                    private var started = 0

                    override fun onActivityStarted(activity: Activity) {
                        if (started++ == 0) trySend(Unit)
                    }

                    override fun onActivityStopped(activity: Activity) {
                        if (started > 0) started--
                    }

                    override fun onActivityCreated(
                        activity: Activity,
                        savedInstanceState: Bundle?,
                    ) = Unit

                    override fun onActivityResumed(activity: Activity) = Unit

                    override fun onActivityPaused(activity: Activity) = Unit

                    override fun onActivitySaveInstanceState(
                        activity: Activity,
                        outState: Bundle,
                    ) = Unit

                    override fun onActivityDestroyed(activity: Activity) = Unit
                }
            application.registerActivityLifecycleCallbacks(callbacks)
            awaitClose { application.unregisterActivityLifecycleCallbacks(callbacks) }
        }
}
