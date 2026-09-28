plugins {
    id("tandem.android.feature")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.clipboard"
}

dependencies {
    // ClipboardSender (E31-06) sends via the real TandemSession seam.
    implementation(project(":core:transport"))
    // TandemSession's DSL builders / Channel / ClipboardText.
    implementation(project(":core:protocol"))
    // ShareTargetActivity/ProcessTextActivity extend TandemActivity (E00-28).
    implementation(project(":core:ui"))

    // ShareTargetActivityTest/ProcessTextActivityTest script TandemSession via FakeTandemSession
    // (E12-11); test-only, never a release classpath.
    testImplementation(testFixtures(project(":core:transport")))
    testImplementation(project(":core:testing"))
}
