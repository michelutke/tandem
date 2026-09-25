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

    // FrameEncoderTest (E11-01) writes into InMemoryDuplexPipe and parses the committed
    // protocol/vectors/frame-encoding.json manifest; test-only, never on a release classpath.
    testImplementation(project(":core:testing"))
    testImplementation(libs.kotlinx.serialization.json)
}

// E11-01: FrameEncoderTest reads the E01-19 vectors committed at protocol/vectors/ (outside this
// Gradle build) directly from the repo, rather than duplicating them as a test resource.
tasks.withType<Test>().configureEach {
    systemProperty("tandem.vectorsDir", rootProject.projectDir.resolve("../protocol/vectors").absolutePath)
}
