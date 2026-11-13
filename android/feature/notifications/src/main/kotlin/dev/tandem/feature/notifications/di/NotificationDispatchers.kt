package dev.tandem.feature.notifications.di

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * E00-18 seam (matches `dev.tandem.app.di.AppDispatchers`): the one place in this module allowed to
 * name a system dispatcher directly (detekt's `InjectedClockOnly` exclude list covers this module's
 * own `di` package).
 */
object NotificationDispatchers {
    val default: CoroutineDispatcher = Dispatchers.Default
}
