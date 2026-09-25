plugins {
    id("tandem.android.library")
    id("tandem.android.hilt")
}

android {
    namespace = "dev.tandem.core.transport"
}

dependencies {
    // JVM TLS 1.3 stack for the E12-04 in-process loopback test server / session-ticket-disable
    // test harness. Test-only: production code uses the platform's built-in Conscrypt provider
    // (ADR-003), never this artifact.
    testImplementation(libs.conscrypt.openjdk.uber)
    // SoftwareIdentityKeyStore/IdentityCertSpec (E10-15) build the client and test-server identity
    // certs; TestClock (E00-18) drives IdentityCertSpec's injected Clock.
    testImplementation(testFixtures(project(":core:crypto")))
    testImplementation(project(":core:testing"))
}
