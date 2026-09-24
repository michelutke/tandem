import com.android.build.api.dsl.LibraryExtension

// AGP 9's built-in Kotlin support compiles Kotlin sources without a separate
// `org.jetbrains.kotlin.android` plugin; jvmTarget follows `compileOptions.targetCompatibility`
// below (see https://kotl.in/gradle/agp-built-in-kotlin).
plugins {
    id("com.android.library")
    id("tandem.android.test-fixtures")
}

extensions.configure<LibraryExtension> {
    compileSdk = 37

    defaultConfig {
        minSdk = 29
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
