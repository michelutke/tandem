package dev.tandem.feature.clipboard.di

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * E00-18 seam (matches `dev.tandem.app.di.AppDispatchers`): the one place in this module allowed
 * to name a system dispatcher directly (detekt's `InjectedClockOnly` exclude list covers this
 * module's own `di` package). [ShareTargetActivity][dev.tandem.feature.clipboard.ShareTargetActivity] and
 * [ProcessTextActivity][dev.tandem.feature.clipboard.ProcessTextActivity] take their
 * `CoroutineDispatcher` as an overridable property defaulting to [default] -- their post-send work
 * (the too-large toast, `finish()`) needs the main thread -- instead of hard-coding
 * `Dispatchers.Main` inline, so tests can substitute an `UnconfinedTestDispatcher`.
 */
object ClipboardDispatchers {
    val default: CoroutineDispatcher = Dispatchers.Main.immediate
}
