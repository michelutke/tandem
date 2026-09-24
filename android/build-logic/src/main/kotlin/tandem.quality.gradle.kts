import io.gitlab.arturbosch.detekt.Detekt
import org.gradle.api.artifacts.VersionCatalogsExtension

// ktlint (formatting, driven by android/.editorconfig) and detekt (static analysis, config in
// android/config/detekt/detekt.yml) for every Android module (E00-05). Custom detekt rules live in
// :lint:detekt-rules (module-dependency rule E00-14, injected-clock rule E00-18).
plugins {
    id("org.jlleitschuh.gradle.ktlint")
    id("io.gitlab.arturbosch.detekt")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

ktlint {
    version.set(libs.findVersion("ktlint").get().requiredVersion)
    filter {
        // Generated protobuf sources are never hand-edited or reformatted (E00-09).
        exclude { it.file.path.contains("/core/protocol/src/main/") }
        exclude { it.file.path.contains("/build/") }
    }
}

detekt {
    toolVersion = libs.findVersion("detekt").get().requiredVersion
    config.setFrom(rootProject.files("config/detekt/detekt.yml"))
    buildUponDefaultConfig = true
    parallel = true
}

// detekt 1.23.x embeds its own Kotlin compiler; keep its tool classpath on that Kotlin version
// instead of letting it align with the project's newer Kotlin.
configurations.matching { it.name == "detekt" || it.name == "detektPlugins" }.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlin") {
            useVersion(libs.findVersion("detekt-kotlin").get().requiredVersion)
        }
    }
}

dependencies {
    "detektPlugins"(project(":lint:detekt-rules"))
}

tasks.withType<Detekt>().configureEach {
    jvmTarget = "17"
    // Patterns are relative to source roots; dev.tandem.protocol.* is generated protobuf code (E00-09).
    exclude("**/dev/tandem/protocol/**")
}
