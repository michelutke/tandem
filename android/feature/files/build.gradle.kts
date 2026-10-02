plugins {
    id("tandem.android.feature")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.files"

    // Local unit tests need a merged manifest (targetSdkVersion) for Robolectric to shadow
    // framework classes -- see feature:notifications' identical setting.
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // FileOffer/FileAccept/FileReject DSL builders and DisplayStringSanitizer (E14-21).
    implementation(project(":core:protocol"))
    // AcceptFlow (E40-07) reads and replies over the real TandemSession seam.
    implementation(project(":core:transport"))
    implementation(libs.kotlinx.coroutines.core)
    // NotificationCompat for NotificationTransferPrompter.
    implementation(libs.androidx.core.ktx)

    // AcceptFlowTest scripts TandemSession via FakeTandemSession (E12-11); test-only.
    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))
    testImplementation(libs.kotlinx.coroutines.test)
}
