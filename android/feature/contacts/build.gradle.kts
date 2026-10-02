plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.contacts"

    // Without this, local unit tests get no merged manifest at all (no targetSdkVersion for
    // Robolectric to resolve), so Robolectric silently falls back to the real (unmocked) SDK
    // stub jar instead of shadowing framework classes -- see tandem.android.compose-ui-test's
    // identical setting/comment for the same reason.
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // Contact/ContactsSyncResponse DSL builders (E51-01).
    implementation(project(":core:protocol"))
    // ContactsSyncSession sends over the real TandemSession seam.
    implementation(project(":core:transport"))
    implementation(libs.kotlinx.coroutines.core)
    // PhoneNormalizer (E51-03).
    implementation(libs.libphonenumber)

    // ContactsSyncSessionTest scripts TandemSession via FakeTandemSession (E12-11); test-only,
    // never a release classpath.
    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))
    testImplementation(libs.kotlinx.coroutines.test)
}
