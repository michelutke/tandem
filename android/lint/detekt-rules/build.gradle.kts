import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Tandem custom detekt rules (E00-05 placeholder; rules added by E00-14 and E00-18). Runs inside
// detekt's own Kotlin 2.0 runtime, so it compiles against the 2.0 language/API level.
plugins {
    id("tandem.kotlin.jvm")
}

// Only the rule classes themselves are loaded into detekt's own Kotlin 2.0 runtime at analysis
// time (via ServiceLoader); the JUnit tests below run in the project's own Kotlin runtime, so
// compileTestKotlin is intentionally left off this restriction.
tasks.named<KotlinCompile>("compileKotlin") {
    compilerOptions {
        languageVersion.set(KotlinVersion.KOTLIN_2_0)
        apiVersion.set(KotlinVersion.KOTLIN_2_0)
    }
}

dependencies {
    compileOnly(libs.detekt.api)
    testImplementation(libs.detekt.api)
    testImplementation(libs.detekt.test)
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
}
