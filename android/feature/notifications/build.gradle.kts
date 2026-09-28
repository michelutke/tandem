plugins {
    id("tandem.android.feature")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.notifications"

    // Without this, local unit tests get no merged manifest at all (no targetSdkVersion for
    // Robolectric to resolve), so Robolectric silently falls back to the real (unmocked) SDK
    // stub jar instead of shadowing framework classes -- see tandem.android.compose-ui-test's
    // identical setting/comment for the same reason.
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // NotificationPosted/NotificationDismiss DSL builders (E30-01).
    implementation(project(":core:protocol"))
    // NotificationSink (E30-16) sends over the real TandemSession seam.
    implementation(project(":core:transport"))

    // NotificationSinkTest scripts TandemSession via FakeTandemSession (E12-11) and
    // ElapsedRealtimeSource via FakeElapsedRealtime (E00-18); test-only, never a release classpath.
    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))
}
