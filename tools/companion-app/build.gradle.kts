// E00-22: separate debug-only Android app, never a dependency of `android/app` and never produced
// by the release pipeline (the release scan at tools/release-audit proves its absence from
// :app's release build). Lives under tools/, not android/, but is a real module of the android/
// build (see android/settings.gradle.kts); reuses that build's version catalog and quality
// convention plugins like every other module.
plugins {
    alias(libs.plugins.android.application)
    id("tandem.quality")
}

android {
    namespace = "dev.tandem.companion"
    compileSdk = 37

    defaultConfig {
        applicationId = "dev.tandem.companion"
        minSdk = 29
        targetSdk = 37
        // Gradle Managed Devices for this module's own instrumented tests (E00-22 tdd); configured
        // directly rather than via `tandem.android.instrumented` for the same reason `app` does:
        // that convention plugin targets `LibraryExtension`, not the `ApplicationExtension` a
        // `com.android.application` module like this one gets.
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

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
}
