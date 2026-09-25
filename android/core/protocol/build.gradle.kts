plugins {
    id("tandem.android.library")
    id("tandem.android.hilt")
}

android {
    namespace = "dev.tandem.core.protocol"
}

dependencies {
    api(libs.protobuf.javalite)
    api(libs.protobuf.kotlin.lite)
    // ChannelMultiplexer (E11-05) exposes Flow/Deferred in its public API, so this is api(), not
    // implementation(): kotlinx-coroutines-core already ships pinned at this exact version via
    // kotlinx-coroutines-test (see docs/dependencies.md), so this adds no new verified artifact.
    api(libs.kotlinx.coroutines.core)

    // FrameEncoderTest (E11-01) writes into InMemoryDuplexPipe and parses the committed
    // protocol/vectors/frame-encoding.json manifest; test-only, never on a release classpath.
    testImplementation(project(":core:testing"))
    testImplementation(libs.kotlinx.serialization.json)

    // Jazzer JUnit fuzz target for FrameDecoder/Envelope (E15-13); test-only, never on a release
    // classpath.
    testImplementation(libs.jazzer.junit)
}

// E11-01: FrameEncoderTest reads the E01-19 vectors committed at protocol/vectors/ (outside this
// Gradle build) directly from the repo, rather than duplicating them as a test resource.
tasks.withType<Test>().configureEach {
    systemProperty("tandem.vectorsDir", rootProject.projectDir.resolve("../protocol/vectors").absolutePath)
}
