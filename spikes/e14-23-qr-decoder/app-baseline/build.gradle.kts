plugins {
    id("com.android.application")
}

android {
    namespace = "com.tandem.spike.qrdecoder.baseline"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.tandem.spike.qrdecoder.baseline"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    packaging {
        resources.excludes.add("META-INF/LICENSE*")
    }
}

// No decoder dependency: this module's APK size is the baseline every decoder's size delta is
// measured against (E14-23 acceptance: APK size delta per option).
