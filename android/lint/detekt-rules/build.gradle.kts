import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Tandem custom detekt rules (E00-05 placeholder; rules added by E00-14 and E00-18). Runs inside
// detekt's own Kotlin 2.0 runtime, so it compiles against the 2.0 language/API level.
plugins {
    id("tandem.kotlin.jvm")
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        languageVersion.set(KotlinVersion.KOTLIN_2_0)
        apiVersion.set(KotlinVersion.KOTLIN_2_0)
    }
}

dependencies {
    compileOnly(libs.detekt.api)
}
