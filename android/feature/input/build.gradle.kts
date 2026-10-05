plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
    id("tandem.android.compose-ui-test")
}

android {
    namespace = "dev.tandem.feature.input"

    // Without this, local unit tests get no merged manifest at all (see :feature:notifications).
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    // GlobalAction/SetText/TextEdit DSL types (E62-01).
    implementation(project(":core:protocol"))

    androidTestImplementation(libs.androidx.test.uiautomator)
}
