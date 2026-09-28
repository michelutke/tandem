package dev.tandem.core.ui

import android.os.Bundle
import androidx.activity.ComponentActivity

/**
 * E00-28 tapjacking baseline: every Tandem activity extends this class (enforced by the
 * `TandemActivityBase` detekt rule, and backstopped by the
 * `TandemActivityTest.everyDeclaredActivity_extendsTandemActivity` Robolectric test in `:app`)
 * instead of `Activity`/`ComponentActivity`/`AppCompatActivity` directly, so
 * `filterTouchesWhenObscured` is always set -- an overlay app must not be able to tap through a
 * partially obscured Tandem screen (invariants 1, 4). `FLAG_SECURE` is deliberately not set here;
 * see docs/planning/decisions.md D-28.
 *
 * Extends `androidx.activity.ComponentActivity` (not the plain framework `Activity`) since
 * Compose's `setContent` requires it; `androidx.activity` is already resolved transitively via
 * Compose tooling and is now also an explicit `:app` dependency (version catalog).
 *
 * Scope limit: `filterTouchesWhenObscured` gates only this activity's own decorView / content
 * subtree (`ViewGroup.dispatchTouchEvent` checks it on every view in that tree). It does **not**
 * cover a `Dialog`, `PopupWindow`, or a Compose `Dialog {}` / `Popup {}` -- each of those opens its
 * own separate window with its own decorView, so a screen that renders sensitive controls inside
 * one of those needs its own `filterTouchesWhenObscured` (or equivalent) if that is ever added.
 *
 * `window.decorView` is read here right after `super.onCreate()`, which forces Android to install
 * the window's decor view immediately. A subclass that still needs `requestWindowFeature(...)`
 * (e.g. `Window.FEATURE_NO_TITLE`) must call it **before** `super.onCreate()` -- calling it
 * afterwards (e.g. from the rest of the subclass's own `onCreate` body) throws
 * `AndroidRuntimeException: requestFeature() must be called before adding content`.
 *
 * Moved here from `:app` (E31-06): feature modules can never depend on `:app` (PRD module
 * rules), and E31-06 added the first feature-module activities (`ShareTargetActivity`,
 * `ProcessTextActivity`), so this class needed a home both `:app` and feature modules can depend
 * on.
 */
open class TandemActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.filterTouchesWhenObscured = true
    }
}
