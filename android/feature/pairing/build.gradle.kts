plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
    id("tandem.android.compose-ui-test")
}

android {
    namespace = "dev.tandem.feature.pairing"
}

dependencies {
    implementation(project(":core:designsystem"))
    // QrPayloadParser/ParseInviteResult/PairingInvite (E14-03).
    implementation(project(":core:pairing"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    // rememberLauncherForActivityResult/ActivityResultContracts for the camera-permission request.
    implementation(libs.androidx.activity.compose)

    // CameraX (E14-10): Preview + ImageAnalysis use cases bound to the screen's lifecycle,
    // PreviewView for the viewfinder (docs/spikes/qr-decoder.md).
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)

    // zxing-cpp (E14-23 spike decision): QR decoding with zero Google/Firebase/telemetry
    // transitive dependencies.
    implementation(libs.zxingcpp.android)
}
