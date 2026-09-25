plugins {
    id("com.android.application")
}

android {
    namespace = "com.tandem.spike.qrdecoder.mlkit"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.tandem.spike.qrdecoder.mlkit"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

dependencies {
    // Bundled model per E14-23: the model ships in the APK, never the Play-services unbundled
    // variant (com.google.android.gms:play-services-mlkit-barcode-scanning).
    implementation("com.google.mlkit:barcode-scanning:17.3.0")

    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
}
