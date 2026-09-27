import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.plugins.JavaPluginExtension
import org.gradle.api.tasks.testing.Test
import org.gradle.kotlin.dsl.getByType
import org.gradle.kotlin.dsl.register

// E15-21: a `jvmIntegrationTest` Gradle source set + task for plain-Kotlin-JVM modules (never
// `tandem.android.library`: this plugin applies `tandem.kotlin.jvm`, which has no `android.jar` on
// any of its configurations, so a module opting in this way can never see an Android framework
// class from this source set, however its main source set is otherwise built). Feature-domain
// modules that keep their sync/protocol-mapping logic behind a framework seam (SPEC.md's
// framework-seam pattern) apply this alongside `tandem.kotlin.jvm` to put an `integration:`-tagged
// suite on the JVM harness classpath (E15-15's join issue) without ever compiling against Android.
// `:harness:jvm-client` (E15-21) itself applies this plugin for its own self-test.
plugins {
    id("tandem.kotlin.jvm")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

val javaExtension = extensions.getByType<JavaPluginExtension>()
val mainSourceSet = javaExtension.sourceSets.getByName("main")
val jvmIntegrationTestSourceSet =
    javaExtension.sourceSets.create("jvmIntegrationTest") {
        compileClasspath += mainSourceSet.output
        runtimeClasspath += mainSourceSet.output
    }

configurations.getByName(jvmIntegrationTestSourceSet.implementationConfigurationName) {
    extendsFrom(configurations.getByName("implementation"))
}
configurations.getByName(jvmIntegrationTestSourceSet.runtimeOnlyConfigurationName) {
    extendsFrom(configurations.getByName("runtimeOnly"))
}

dependencies {
    add(jvmIntegrationTestSourceSet.implementationConfigurationName, libs.findLibrary("junit-jupiter").get())
    add(jvmIntegrationTestSourceSet.runtimeOnlyConfigurationName, libs.findLibrary("junit-platform-launcher").get())
}

// Deliberately not wired into `check`/`test` (like the not-yet-wired conformance/pcap-audit tools
// noted in CLAUDE.md): E40/E50/E51 wire `jvmIntegrationTest` into whatever CI job needs it later.
tasks.register<Test>("jvmIntegrationTest") {
    group = "verification"
    description = "E15-21: runs the jvmIntegrationTest source set (plain-JVM `integration:` tests, no Android classes)."
    testClassesDirs = jvmIntegrationTestSourceSet.output.classesDirs
    classpath = jvmIntegrationTestSourceSet.runtimeClasspath
    useJUnitPlatform()
}
