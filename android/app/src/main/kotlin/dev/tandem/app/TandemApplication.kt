package dev.tandem.app

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

// Root Hilt application (E00-03). The generated `Hilt_TandemApplication` superclass builds the
// real `SingletonComponent` from every `@Module @InstallIn` shell on the app's classpath; no
// production bindings live here yet.
@HiltAndroidApp
class TandemApplication : Application()
