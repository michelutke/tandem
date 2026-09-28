plugins {
    id("tandem.android.library")
    id("tandem.android.hilt")
}

android {
    namespace = "dev.tandem.core.transport"

    // FakeTandemSession (E12-11) lives here so feature tests consume it via testFixtures, never a
    // release classpath (E00-18 pattern).
    testFixtures {
        enable = true
    }
}

dependencies {
    // TandemSession (E12-11) exposes ChannelMultiplexer/VersionHandshake/ConnectionStateMachine
    // (E12-08) and their Envelope/Channel wire types in its own public API, so this is api(), not
    // implementation().
    api(project(":core:protocol"))

    // PairedMacBonjourSource (E20-06) matches resolved services against paired fingerprints via
    // PairedMacMatcher/ServiceDiscovery (E21-04/E21-05); implementation(), never api() -- neither
    // type appears in this module's own public API.
    implementation(project(":core:discovery"))
    implementation(project(":core:crypto"))

    // ByteStreamSessionTest wires two sessions over InMemoryDuplexPipe (E00-19); test-only, never
    // a release classpath.
    testImplementation(project(":core:testing"))
    // PairedMacBonjourSourceTest scripts ServiceDiscovery via FakeServiceDiscovery (E21-04);
    // test-only, never a release classpath.
    testImplementation(testFixtures(project(":core:discovery")))
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
