import com.android.build.api.dsl.CommonExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

// Compose `ui:` test wiring (Compose UI test rule, Espresso actions) on top of the off-device
// JUnit4/Robolectric harness (`tandem.android.robolectric`, E00-20); split out so modules that only
// need a Robolectric-modeled `Context`/`ClipboardManager` (e.g. `core:storage`'s Room tests,
// E13-02) don't have to build Compose and carry its test-only dependencies too.
// `includeAndroidResources` makes local unit tests reuse the `debug` variant's fully
// resource-linked manifest and resource apk, which is what makes the `ui-test-manifest` test
// activity below resolvable.
plugins {
    id("org.jetbrains.kotlin.plugin.compose")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

extensions.configure<CommonExtension> {
    buildFeatures.compose = true
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    "testImplementation"(platform(libs.findLibrary("androidx-compose-bom").get()))
    "testImplementation"(libs.findLibrary("androidx-compose-ui-test-junit4").get())
    // `debugImplementation`, not `testImplementation`: its themed `ComponentActivity` manifest
    // entry only resolves (styles included) through the `debug` variant's full resource link;
    // local unit tests reuse that linked debug resource apk (`includeAndroidResources`).
    "debugImplementation"(platform(libs.findLibrary("androidx-compose-bom").get()))
    "debugImplementation"(libs.findLibrary("androidx-compose-ui-test-manifest").get())
    // Force espresso-core past the 3.5.0 pulled in transitively: that version's
    // InputManagerEventInjectionStrategy reflects on a real-device API removed from API 37's
    // android-all jar (https://github.com/robolectric/robolectric/issues/11344).
    "testImplementation"(libs.findLibrary("androidx-test-espresso-core").get())
}
