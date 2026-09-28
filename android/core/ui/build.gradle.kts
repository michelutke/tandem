plugins {
    id("tandem.android.library")
    id("tandem.android.robolectric")
}

android {
    namespace = "dev.tandem.core.ui"

    // TandemActivityTest needs a merged manifest for Robolectric to resolve targetSdkVersion from
    // -- without this, Robolectric silently falls back to the real (unmocked) SDK stub jar instead
    // of shadowing framework classes (same reasoning as tandem.android.compose-ui-test's identical
    // setting).
    testOptions.unitTests.isIncludeAndroidResources = true
}

dependencies {
    // Aligns androidx.activity's own transitive androidx.compose.runtime-annotation resolution
    // with the same BOM :app uses, matching :app's own dependency comment for this exact pairing;
    // without it this module resolves an old, unverified runtime-annotation version standalone.
    api(platform(libs.androidx.compose.bom))
    // TandemActivity (E00-28) extends ComponentActivity -- api(), not implementation(): every
    // module extending TandemActivity needs ComponentActivity itself on its own compile classpath.
    api(libs.androidx.activity)
}
