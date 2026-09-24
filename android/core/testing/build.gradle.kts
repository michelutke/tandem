plugins {
    id("tandem.android.library")
}

android {
    namespace = "dev.tandem.core.testing"
}

// Test fixtures for other modules: consume only via testImplementation (never a release classpath).
dependencies {
    api(project(":core:transport"))
    api(libs.kotlinx.coroutines.test)
    api(libs.junit.jupiter)
}
