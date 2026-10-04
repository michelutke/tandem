package dev.tandem.feature.messaging

import android.app.Activity
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.IBinder

/** Test-only no-op components that make the androidTest APK eligible for the default SMS role. */
class StubSmsComposeActivity : Activity()

class StubSmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) = Unit
}

class StubWapPushDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) = Unit
}

class StubRespondViaMessageService : Service() {
    override fun onBind(intent: Intent): IBinder? = null
}
