plugins {
    id("tandem.android.library")
    id("tandem.android.hilt")
    // Room's Android-variant `Room.databaseBuilder`/`inMemoryDatabaseBuilder` require a `Context`
    // even with a driver injected (the context-less KMP entry point is only published on the
    // plain-JVM variant, not this module's Android-variant artifact); TrustStoreTest gets a
    // working `Context` via Robolectric's `RuntimeEnvironment.getApplication()` (E00-20). This is
    // a deviation from the E13-01 spike's Finding 1 ("neither technology needs Robolectric") --
    // see the coder's report for E13-02.
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.core.storage"
}

dependencies {
    // SpkiFingerprint (E10-03) is the trust store's only key type (invariant 3, CLAUDE.md).
    implementation(project(":core:crypto"))

    implementation(libs.room.runtime)
    ksp(libs.room.compiler)

    // AndroidSQLiteDriver wraps the OS's built-in SQLite (androidx.sqlite:sqlite-framework);
    // Robolectric shadows the same framework SQLite classes, so this one driver works unchanged
    // in production and in TrustStoreTest (E13-02; see TrustStore's KDoc for why the JNI-compiled
    // BundledSQLiteDriver the E13-01 spike used cannot load in this module -- its native library
    // is packaged for on-device extraction, not for a host JVM's `java.library.path`).
    implementation(libs.sqlite.framework)
}

// E13-01/E13-02: Room schema export feeds the migration fixture E13-03 commits under test
// resources.
ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
    arg("room.generateKotlin", "true")
}
