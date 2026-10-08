plugins {
    id("tandem.android.feature")
}

android {
    namespace = "dev.tandem.feature.calls"
}

dependencies {
    // CallEvent/CallAction/PlaceCallRequest/CallActionResult DSL builders (E52-01).
    implementation(project(":core:protocol"))
    // CallDetector and the handlers send over the real TandemSession seam.
    implementation(project(":core:transport"))
    implementation(libs.kotlinx.coroutines.core)
    // TapToCallActivity extends TandemActivity (E00-28 tapjacking baseline).
    implementation(project(":core:ui"))
    // Tap-to-call notification (NotificationCompat).
    implementation(libs.androidx.core)

    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))
    testImplementation(libs.kotlinx.coroutines.test)
}
