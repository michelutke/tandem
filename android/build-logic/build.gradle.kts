plugins {
    `kotlin-dsl`
}

group = "dev.tandem.buildlogic"

// E00-29: lock build-logic's own dependency graph too; regenerate with
// `./gradlew --write-locks` from android/build-logic.
dependencyLocking {
    lockAllConfigurations()
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // `implementation` (not `compileOnly`) so these plugins are also on the runtime classpath
    // that GradleTestKit's `withPluginClasspath()` picks up for the convention-plugin tests below.
    implementation(libs.android.gradlePlugin)
    implementation(libs.kotlin.gradlePlugin)
    implementation(libs.kotlin.composeCompiler.gradlePlugin)
    implementation(libs.ktlint.gradlePlugin)
    implementation(libs.detekt.gradlePlugin)
    implementation(libs.ksp.gradlePlugin)
    implementation(libs.hilt.gradlePlugin)
    implementation(libs.kover.gradlePlugin)

    testImplementation(libs.junit.jupiter)
    testImplementation(gradleTestKit())
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    systemProperty("tandem.androidProjectDir", rootDir.parentFile.absolutePath)
}
