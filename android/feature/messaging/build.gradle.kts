plugins {
    id("tandem.android.feature")
    id("tandem.android.instrumented")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.feature.messaging"

    // Without this, local unit tests get no merged manifest at all (no targetSdkVersion for
    // Robolectric to resolve) -- same reason as :feature:contacts.
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // SmsMessage/SmsThread protocol types (E50-01).
    implementation(project(":core:protocol"))
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.turbine)
}
