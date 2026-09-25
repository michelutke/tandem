import com.android.build.api.dsl.CommonExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

// Opt-in JVM test harness for modules that need an Android framework type Robolectric can model
// (Context, ClipboardManager, ...), e.g. Room's Android-variant `Room.databaseBuilder` (E13-02).
// JUnit4 + the JUnit Vintage engine run `@RunWith(AndroidJUnit4::class)` (which delegates to
// `RobolectricTestRunner` off device) tests on the same `useJUnitPlatform()` test task as JUnit5
// Jupiter tests (wired by `tandem.android.test-fixtures`), so both land in the same test task's
// JUnit XML report. Compose `ui:` tests need this plus `tandem.android.compose-ui-test`.
val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

extensions.configure<CommonExtension> {
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
    // AndroidJUnit4 (delegates to RobolectricTestRunner off-device).
    "testImplementation"(libs.findLibrary("androidx-test-ext-junit").get())
}
