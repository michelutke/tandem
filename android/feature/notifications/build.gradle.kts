plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
    id("tandem.android.compose-ui-test")
}

android {
    namespace = "dev.tandem.feature.notifications"

    // Without this, local unit tests get no merged manifest at all (no targetSdkVersion for
    // Robolectric to resolve), so Robolectric silently falls back to the real (unmocked) SDK
    // stub jar instead of shadowing framework classes -- see tandem.android.compose-ui-test's
    // identical setting/comment for the same reason.
    testOptions.unitTests.isIncludeAndroidResources = true
}

// E00-33: SecretVisibilityInstrumentedTest posts through the companion app (E00-22), so its debug
// APK ships as an androidTest asset and the test installs it onto the managed device before posting.
abstract class CopyCompanionApk : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val apkDir: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val apk = apkDir.get().asFile.listFiles { file -> file.extension == "apk" }.orEmpty().single()
        apk.copyTo(outputDir.get().asFile.resolve("companion.apk"), overwrite = true)
    }
}

val copyCompanionApk by tasks.registering(CopyCompanionApk::class) {
    dependsOn(":companion-app:assembleDebug")
    apkDir.set(project(":companion-app").layout.buildDirectory.dir("outputs/apk/debug"))
}

extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {
    onVariants { variant ->
        variant.androidTest?.sources?.assets?.addGeneratedSourceDirectory(copyCompanionApk, CopyCompanionApk::outputDir)
    }
}

dependencies {
    // NotificationPosted/NotificationDismiss DSL builders (E30-01).
    implementation(project(":core:protocol"))
    // NotificationSink (E30-16) sends over the real TandemSession seam.
    implementation(project(":core:transport"))
    // SettingsStore (E13-04): PerAppNotificationFilter's (E30-04) and IconSender's (E30-05)
    // DataStore-backed overrides/sent-icon records.
    implementation(project(":core:storage"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.androidx.datastore.preferences.core)

    // PerAppNotificationFilterScreen (E30-04).
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    // Bitmap.createBitmap KTX extension (E30-05's IconEncoder).
    implementation(libs.androidx.core.ktx)

    // NotificationSinkTest scripts TandemSession via FakeTandemSession (E12-11) and
    // ElapsedRealtimeSource via FakeElapsedRealtime (E00-18); test-only, never a release classpath.
    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))
    testImplementation(libs.kotlinx.coroutines.test)
}
