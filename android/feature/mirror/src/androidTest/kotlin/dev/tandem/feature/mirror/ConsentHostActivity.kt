package dev.tandem.feature.mirror

import android.app.Activity
import android.content.Intent
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Test host that launches the consent intent for a result and records it (E61-02 instrumented tests). */
@Suppress("DEPRECATION")
class ConsentHostActivity : Activity() {
    @Volatile
    var resultCode: Int? = null
        private set

    @Volatile
    private var resultDelivered = CountDownLatch(1)

    fun awaitResult(timeoutMs: Long): Boolean = resultDelivered.await(timeoutMs, TimeUnit.MILLISECONDS)

    fun relaunchForResult(intent: Intent) {
        resultCode = null
        resultDelivered = CountDownLatch(1)
        launchForResult(intent)
    }

    fun launchForResult(intent: Intent) {
        startActivityForResult(intent, CONSENT_REQUEST_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (requestCode == CONSENT_REQUEST_CODE) {
            this.resultCode = resultCode
            resultDelivered.countDown()
        }
    }

    private companion object {
        const val CONSENT_REQUEST_CODE = 1
    }
}
