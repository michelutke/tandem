import org.gradle.api.artifacts.VersionCatalogsExtension

// Hilt DI wiring skeleton (E00-03). Every module that declares a `@Module @InstallIn` shell, or
// the `app` module's `@HiltAndroidApp` application, applies this on top of its own AGP convention
// plugin (`tandem.android.library` / `tandem.android.instrumented`, or `com.android.application`
// directly for `app`). KSP replaces kapt: AGP 9's built-in Kotlin support dropped kapt
// compatibility (https://developer.android.com/build/migrate-to-built-in-kotlin), and Dagger/Hilt
// KSP support has been stable since Dagger 2.60 (dagger.dev/dev-guide/ksp.html). The Hilt Gradle
// plugin itself requires Dagger 2.59+ for AGP 9 (https://github.com/google/dagger/releases/tag/dagger-2.59,
// with AGP-9-specific fixes through 2.60.1); the version pinned in the catalog is the first stable
// release covering both requirements.
plugins {
    id("com.google.devtools.ksp")
    id("com.google.dagger.hilt.android")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

dependencies {
    "implementation"(libs.findLibrary("hilt-android").get())
    "ksp"(libs.findLibrary("hilt-compiler").get())
}
