plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
    id("tandem.android.compose-ui-test")
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
    // MediaPermissionRequestActivity extends TandemActivity (E00-28).
    implementation(project(":core:ui"))
    implementation(libs.androidx.core)
    // AcceptFlow (E40-07) reads and replies over the real TandemSession seam.
    implementation(project(":core:transport"))
    implementation(libs.kotlinx.coroutines.core)
    // FileReceiver implements PeerDataPurging so unpair deletes retained .part files (E14-12).
    implementation(project(":core:pairing"))
    implementation(project(":core:crypto"))
    // NotificationCompat for NotificationTransferPrompter.
    implementation(libs.androidx.core.ktx)
    // TransferProgressRow (E40-12).
    implementation(project(":core:designsystem"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)

    // AcceptFlowTest scripts TandemSession via FakeTandemSession (E12-11); test-only.
    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))
    testImplementation(libs.kotlinx.coroutines.test)
}
