plugins {
    id("tandem.android.library")
}

android {
    namespace = "dev.tandem.core.crypto"

    // SoftwareIdentityKeyStore (E10-15) lives here so JVM tests exercise the same module as the
    // real AndroidKeyStore impl; testFixtures is never on a release classpath (E00-18 pattern).
    testFixtures {
        enable = true
    }
}
