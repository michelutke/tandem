plugins {
    alias(libs.plugins.android.application)
    id("tandem.android.test-fixtures")
    id("tandem.android.robolectric")
    id("tandem.android.compose-ui-test")
    id("tandem.android.hilt")
    id("tandem.quality")
}

android {
    namespace = "dev.tandem.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "dev.tandem.app"
        minSdk = 29
        targetSdk = 37
        // Gradle Managed Devices for `instrumented:` tdd entries (E00-21); `app` configures these
        // directly rather than applying `tandem.android.instrumented` because that convention
        // plugin targets `LibraryExtension`, not the `ApplicationExtension` a
        // `com.android.application` module like this one gets (see android-instrumented.yml for
        // known emulator limits).
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

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    // TandemActivity (E00-28) extends ComponentActivity; pinned explicitly even though it also
    // resolves transitively via activity-compose (see the version catalog comment).
    implementation(libs.androidx.activity)
    implementation(libs.androidx.activity.compose)
    // E20-18: ActivityStore persists the metadata-only feed in a Preferences DataStore.
    implementation(libs.androidx.datastore.preferences.core)
    implementation(libs.kotlinx.coroutines.core)

    // E00-03 Hilt DI wiring skeleton: app assembles the SingletonComponent from every core
    // module's empty @Module @InstallIn shell.
    implementation(project(":core:crypto"))
    // E20-17: Home screen composables (TitleBlock, DotRing, FloatingToolbar, CookieFab, etc.).
    implementation(project(":core:designsystem"))
    implementation(project(":core:pairing"))
    implementation(project(":core:protocol"))
    implementation(project(":core:storage"))
    implementation(project(":core:transport"))
    // TandemActivity (E00-28), moved out of :app in E31-06 so feature modules can extend it too.
    implementation(project(":core:ui"))
    // E20-14: sequences onboarding's final step to E14-10's ScannerScreen unmodified.
    implementation(project(":feature:pairing"))
    // E30-02: TandemNotificationListenerService, declared below in this module's manifest.
    implementation(project(":feature:notifications"))
    // E31-06: ShareTargetActivity/ProcessTextActivity, declared below in this module's manifest.
    implementation(project(":feature:clipboard"))
    // E40-11: ShareFilesActivity, declared below in this module's manifest.
    implementation(project(":feature:files"))
    // E61-02: MirrorCaptureService (mediaProjection foreground service), merged from this module's manifest.
    implementation(project(":feature:mirror"))

    // FakeTandemSession (E12-11) for ClipboardWriterTest (E31-05) and RingController's tests
    // (E23-06); FakeElapsedRealtime (E00-18) for E23-06, matching how core/pairing tests a
    // TandemSession-taking handler. Test-only.
    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))

    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    // E23-06: RingStopActionReceiverInstrumentedTest drives RingController with a FakeTandemSession.
    androidTestImplementation(testFixtures(project(":core:transport")))
}
