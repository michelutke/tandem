import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.artifacts.VersionCatalogsExtension

// Gradle Managed Devices for `instrumented:` tdd entries (E00-21). Modules opt in by applying
// this plugin instead of `tandem.android.library`; it wires the AndroidJUnitRunner instrumentation
// runner, the androidx.test dependencies every androidTest needs, and the two managed devices the
// android-instrumented workflow runs: `api29` (google) and `api35` (google_apis). See
// android-instrumented.yml for known emulator limits (no StrongBox, emulated TEE, no camera QR
// scan, telephony via `adb emu` only, MediaProjection consent needs UiAutomator).
plugins {
    id("tandem.android.library")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

extensions.configure<LibraryExtension> {
    defaultConfig {
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    testOptions {
        managedDevices {
            localDevices {
                create("api29") {
                    device = "Pixel 6"
                    apiLevel = 29
                    require64Bit = true
                    // No ATD image exists below API 30, so API 29 uses the regular Google image.
                    systemImageSource = "google"
                }
                create("api35") {
                    device = "Pixel 6"
                    apiLevel = 35
                    require64Bit = true
                    systemImageSource = "google_apis"
                }
            }
            groups {
                create("ci") {
                    targetDevices.add(allDevices["api29"])
                    targetDevices.add(allDevices["api35"])
                }
            }
        }
    }
}

dependencies {
    "androidTestImplementation"(libs.findLibrary("androidx-test-runner").get())
    "androidTestImplementation"(libs.findLibrary("androidx-test-ext-junit").get())
}
