plugins {
    id("tandem.android.library")
    id("tandem.android.robolectric")
    id("tandem.android.compose-ui-test")
}

android {
    namespace = "dev.tandem.core.designsystem"
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(platform(libs.androidx.compose.bom))
    debugImplementation(libs.androidx.compose.ui.tooling)
}
