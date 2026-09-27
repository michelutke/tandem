package dev.tandem.app.di

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * E00-18 seam: the one place in `:app` allowed to name a system dispatcher directly
 * (`detekt.yml`'s `InjectedClockOnly` exclude list covers the `di` package). [TandemApplication]
 * and [dev.tandem.app.service.TandemService] take their [CoroutineDispatcher] as an overridable
 * property defaulting to [default] instead of hard-coding `Dispatchers.Default` inline, so tests
 * can substitute a `TestDispatcher`.
 */
object AppDispatchers {
    val default: CoroutineDispatcher = Dispatchers.Default
}
