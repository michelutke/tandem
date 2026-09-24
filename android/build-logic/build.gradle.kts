plugins {
    `kotlin-dsl`
}

group = "dev.tandem.buildlogic"

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

    testImplementation(libs.junit.jupiter)
    testImplementation(gradleTestKit())
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    systemProperty("tandem.androidProjectDir", rootDir.parentFile.absolutePath)
}
