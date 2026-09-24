import com.android.build.api.dsl.CommonExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

// Opt-in JVM test harness for modules that need an Android framework type Robolectric can model
// (Context, ClipboardManager, ...) or a Compose `ui:` test (E00-20). JUnit4 + the JUnit Vintage
// engine run `@RunWith(AndroidJUnit4::class)` (which delegates to `RobolectricTestRunner` off
// device) tests on the same `useJUnitPlatform()` test task as JUnit5 Jupiter tests (wired by
// `tandem.android.test-fixtures`), so both land in the same test task's JUnit XML report.
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
    // Robolectric needs these opened on JDK 17+ to reach internal OpenJDK APIs
    // (https://robolectric.org/getting-started/#running-with-java-17-and-higher).
    testOptions.unitTests.all {
        it.jvmArgs(
            "--add-opens=java.base/java.lang=ALL-UNNAMED",
            "--add-opens=java.base/java.util=ALL-UNNAMED",
            "--add-opens=java.base/java.io=ALL-UNNAMED",
            "--add-opens=java.base/java.net=ALL-UNNAMED",
            "--add-opens=java.base/java.security=ALL-UNNAMED",
            "--add-opens=java.base/java.text=ALL-UNNAMED",
            "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
            "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED",
            "--add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED",
        )
    }
}

dependencies {
    "testImplementation"(libs.findLibrary("junit4").get())
    "testRuntimeOnly"(libs.findLibrary("junit-vintage-engine").get())
    "testImplementation"(libs.findLibrary("robolectric").get())
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
    "testImplementation"(libs.findLibrary("androidx-test-ext-junit").get())
}
