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
    // TandemSession/ConnectionState, exposed in PairingConnector/PairingStateMachine's own public
    // API (E14-05), so this is api(), not implementation() -- mirrors core/transport's own
    // api(":core:protocol").
    api(project(":core:transport"))
    testImplementation(testFixtures(project(":core:transport")))

    // QrPayloadParserTest (E14-03) parses the committed protocol/vectors/qr-payload.json manifest;
    // test-only, never on a release classpath.
    testImplementation(libs.kotlinx.serialization.json)
    // SoftwareIdentityKeyStore for PairRequestBuilderTest (E14-06); test-only.
    testImplementation(testFixtures(project(":core:crypto")))
    // FakeTandemSession (E12-11) for PairingStateMachineTest (E14-05); test-only.
    // TestClock/StandardTestDispatcher pairing for virtual-time timeouts (E00-18); test-only.
    testImplementation(project(":core:testing"))
    // Jazzer JUnit fuzz target for QrPayloadParser (E71-03); test-only, never on a release classpath.
    testImplementation(libs.jazzer.junit)
}

// E14-03: QrPayloadParserTest reads the E01-21 vectors committed at protocol/vectors/ (outside this
// Gradle build) directly from the repo, rather than duplicating them as a test resource.
tasks.withType<Test>().configureEach {
    systemProperty("tandem.vectorsDir", rootProject.projectDir.resolve("../protocol/vectors").absolutePath)
}
