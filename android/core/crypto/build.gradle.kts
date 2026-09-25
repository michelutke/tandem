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
}
