plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.files"

    // Same reason as :feature:status -- Robolectric needs a merged manifest with targetSdkVersion.
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // PhotoPageResult / PhotoAccess (E41-01).
    implementation(project(":core:protocol"))
    // MediaPermissionRequestActivity extends TandemActivity (E00-28).
    implementation(project(":core:ui"))
    implementation(libs.androidx.core)
}
