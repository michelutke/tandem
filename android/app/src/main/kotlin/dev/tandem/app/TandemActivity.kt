package dev.tandem.app

import android.app.Activity
import android.os.Bundle

/**
 * E00-28 tapjacking baseline: every Tandem activity extends this class (enforced by the
 * `TandemActivityBase` detekt rule) instead of `Activity`/`ComponentActivity`/`AppCompatActivity`
 * directly, so `filterTouchesWhenObscured` is always set — an overlay app must not be able to tap
 * through a partially obscured Tandem screen (invariants 1, 4). `FLAG_SECURE` is deliberately not
 * set here; see docs/planning/decisions.md D-28.
 */
open class TandemActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.filterTouchesWhenObscured = true
    }
}
