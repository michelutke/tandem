package dev.tandem.feature.mirror

import android.app.Activity
import android.content.Intent

/** Test host that launches the consent intent for a result and records it (E61-02 instrumented tests). */
@Suppress("DEPRECATION")
class ConsentHostActivity : Activity() {
    @Volatile
    var resultCode: Int? = null
        private set

    fun launchForResult(intent: Intent) {
        startActivityForResult(intent, CONSENT_REQUEST_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (requestCode == CONSENT_REQUEST_CODE) this.resultCode = resultCode
    }

    private companion object {
        const val CONSENT_REQUEST_CODE = 1
    }
}
