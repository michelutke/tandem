package dev.tandem.app.di

import java.time.Clock

/** E00-18 seam: the one place in `:app` allowed to name the system [Clock] (`di` is excluded). */
object AppClock {
    val system: Clock = Clock.systemUTC()
}
