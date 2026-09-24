import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

// Shared test dependencies and JUnit Platform wiring for every `tandem.android.library` (and,
// transitively, `tandem.android.feature`) module: JUnit Jupiter + the platform launcher so
// `./gradlew test` runs on JUnit5, and Turbine + kotlinx-coroutines-test for Flow assertions.
// Re-applying `com.android.library` here is a no-op (already applied by the consuming module)
// but gives this script its own `LibraryExtension` and `testImplementation`/`testRuntimeOnly`
// configuration accessors. Precompiled script plugins don't get the generated `libs.*` accessors
// that a project's own build script gets, so the version catalog is looked up by name instead.
val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

extensions.configure<LibraryExtension> {
    testOptions {
        unitTests.all {
            it.useJUnitPlatform()
        }
    }
}

dependencies {
    "testImplementation"(libs.findLibrary("junit-jupiter").get())
    "testRuntimeOnly"(libs.findLibrary("junit-platform-launcher").get())
    "testImplementation"(libs.findLibrary("turbine").get())
    "testImplementation"(libs.findLibrary("kotlinx-coroutines-test").get())
}
