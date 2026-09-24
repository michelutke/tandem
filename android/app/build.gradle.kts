plugins {
    alias(libs.plugins.android.application)
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
