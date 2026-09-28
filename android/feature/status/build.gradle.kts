plugins {
    id("tandem.android.feature")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.status"

    // Without this, local unit tests get no merged manifest at all (no targetSdkVersion for
    // Robolectric to resolve), so Robolectric silently falls back to the real (unmocked) SDK
    // stub jar instead of shadowing framework classes -- see tandem.android.compose-ui-test's
    // identical setting/comment for the same reason.
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // DeviceStatus/NetworkType DSL (E01-13).
    implementation(project(":core:protocol"))
    // ContextCompat.registerReceiver's RECEIVER_NOT_EXPORTED flag (E23-02).
    implementation(libs.androidx.core)
}
