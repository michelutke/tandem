plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.mirror"

    // Without this, local unit tests get no merged manifest at all (see :feature:status).
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // Drives the system MediaProjection consent dialog (E61-02 instrumented tests).
    androidTestImplementation(libs.androidx.test.uiautomator)
}
