import com.android.build.api.dsl.CommonExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

// Shared test dependencies and JUnit Platform wiring for every `tandem.android.library` (and,
// transitively, `tandem.android.feature`) module, plus `app` (which applies this plugin directly
// since it uses `com.android.application` rather than the library convention plugin): JUnit
// Jupiter + the platform launcher so `./gradlew test` runs on JUnit5, and Turbine +
// kotlinx-coroutines-test for Flow assertions. `CommonExtension` is the DSL type shared by
// `LibraryExtension` and `ApplicationExtension`, so this configures whichever one the consuming
// module already applied. Precompiled script plugins don't get the generated `libs.*` accessors
// that a project's own build script gets, so the version catalog is looked up by name instead.
val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

extensions.configure<CommonExtension> {
    testOptions.unitTests.all {
        it.useJUnitPlatform()
    }
}

dependencies {
    "testImplementation"(libs.findLibrary("junit-jupiter").get())
    "testRuntimeOnly"(libs.findLibrary("junit-platform-launcher").get())
    "testImplementation"(libs.findLibrary("turbine").get())
    "testImplementation"(libs.findLibrary("kotlinx-coroutines-test").get())
}
