plugins {
    id("tandem.android.instrumented")
    id("tandem.android.hilt")
}

android {
    namespace = "dev.tandem.core.crypto"

    // SoftwareIdentityKeyStore (E10-15) lives here so JVM tests exercise the same module as the
    // real AndroidKeyStore impl; testFixtures is never on a release classpath (E00-18 pattern).
    testFixtures {
        enable = true
    }
}

dependencies {
    // TestClock (E00-18) for IdentityCertSpec's injected-Clock unit tests.
    testImplementation(project(":core:testing"))

    // SpkiFingerprintTest (E10-03) parses the committed protocol/vectors/spki-fingerprint.json manifest.
    testImplementation(libs.kotlinx.serialization.json)
}

// E10-03: SpkiFingerprintTest reads the E01-17 vectors committed at protocol/vectors/ (outside this
// Gradle build) directly from the repo, rather than duplicating them as a test resource.
tasks.withType<Test>().configureEach {
    systemProperty("tandem.vectorsDir", rootProject.projectDir.resolve("../protocol/vectors").absolutePath)
}
