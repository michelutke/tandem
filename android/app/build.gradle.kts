plugins {
    alias(libs.plugins.android.application)
    id("tandem.android.test-fixtures")
    id("tandem.android.robolectric")
    id("tandem.quality")
}

android {
    namespace = "dev.tandem.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "dev.tandem.app"
        minSdk = 29
        targetSdk = 37
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    // TandemActivity (E00-28) extends ComponentActivity; pinned explicitly even though it also
    // resolves transitively via activity-compose (see the version catalog comment).
    implementation(libs.androidx.activity)
}
