plugins {
    id("tandem.android.library")
    id("tandem.android.hilt")
}

android {
    namespace = "dev.tandem.core.pairing"
}

dependencies {
    implementation(project(":core:protocol"))
    // PinSource/SpkiFingerprint for QrPairingPinSource (E14-04).
    implementation(project(":core:crypto"))
    // TandemSession for RevokeHandler (E14-19).
    implementation(project(":core:transport"))
    testImplementation(testFixtures(project(":core:transport")))

    // QrPayloadParserTest (E14-03) parses the committed protocol/vectors/qr-payload.json manifest;
    // test-only, never on a release classpath.
    testImplementation(libs.kotlinx.serialization.json)
}

// E14-03: QrPayloadParserTest reads the E01-21 vectors committed at protocol/vectors/ (outside this
// Gradle build) directly from the repo, rather than duplicating them as a test resource.
tasks.withType<Test>().configureEach {
    systemProperty("tandem.vectorsDir", rootProject.projectDir.resolve("../protocol/vectors").absolutePath)
}
