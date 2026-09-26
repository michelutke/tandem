import org.gradle.api.attributes.Attribute
import org.gradle.api.tasks.JavaExec
import org.gradle.api.tasks.testing.Test

// E15-21: the JVM harness client. Links the real Android `core/protocol`, `core/crypto`,
// `core/transport` and `core/pairing` modules (not a reimplementation) onto a genuine JVM
// classpath, driven by a small stdin/stdout CLI (connect, pair, confirm, disconnect, exit).
// `tandem.jvm-integration-test` (this module's own self-test, an `integration:`-tier suite
// against an in-process Conscrypt TLS server) also makes this module the first real consumer of
// the `jvmIntegrationTest` convention it introduces for later `feature/*` phases (E40/E50/E51).
//
// Deliberately not the `application` plugin: its `distTar`/`distZip`/`installDist` tasks flatten
// every runtime-classpath entry into one `lib/` directory by file name, and every `core/*`
// (AGP `tandem.android.library`) module's compiled-classes jar is literally named `full.jar` on
// disk (E15-21: this harness is the first module to put several of them on one classpath at
// once), so those tasks fail on the resulting name collision. `run` below replicates only the
// one piece of the plugin this harness actually needs.
plugins {
    id("tandem.jvm-integration-test")
}

val harnessMainClass = "dev.tandem.harness.jvmclient.HarnessCliKt"

// `core/*` are `tandem.android.library` modules (AGP), each publishing a `debug`/`release`
// `BuildTypeAttr` pair of variants, further split by `artifactType` (android-classes-jar, aar,
// android-manifest, ...). A plain `tandem.kotlin.jvm` consumer's `compileClasspath`/
// `runtimeClasspath` request neither attribute, which AGP's variants otherwise leave ambiguous
// (E15-21: this is the actual problem the harness module exists to solve — linking real
// `core/*` Android-library modules onto a genuine JVM classpath). Requesting both attributes on
// every resolvable configuration here (not just a module's own direct `project(...)` edges) makes
// the same disambiguation apply transitively, e.g. `core:pairing`'s own `api(project(":core:transport"))`.
//
// `core/crypto`, `core/transport` and `core/pairing` also apply `tandem.android.hilt` for their
// `@Module @InstallIn` wiring inside the real app; that DI graph is unreachable from this harness
// (nothing here touches a Hilt component or `@AndroidEntryPoint`), but Gradle still resolves the
// whole `hilt-android` dependency, whose own androidx transitives (`androidx.savedstate`,
// `androidx.lifecycle`, ...) publish Android-only (`aar`) variants with no plain-jar runtime
// artifact a JVM classpath can use. Excluding `hilt-android` on every resolvable configuration
// drops that entire subtree wherever it enters the graph.
val androidBuildTypeAttribute: Attribute<String> =
    Attribute.of("com.android.build.api.attributes.BuildTypeAttr", String::class.java)
val artifactTypeAttribute: Attribute<String> = Attribute.of("artifactType", String::class.java)

configurations.matching { it.isCanBeResolved }.configureEach {
    attributes {
        attribute(androidBuildTypeAttribute, "debug")
        attribute(artifactTypeAttribute, "jar")
    }
    exclude(group = "com.google.dagger", module = "hilt-android")
}

dependencies {
    implementation(project(":core:crypto"))
    implementation(project(":core:transport"))
    implementation(project(":core:pairing"))
    implementation(project(":core:protocol"))
    // SoftwareIdentityKeyStore (E10-15) is this harness's only IdentityKeyStore, wrapped by
    // PersistentIdentityKeyStore for cross-restart persistence (E15-21 acceptance); this module
    // never ships (no `:app` dependency reaches it), so depending on a testFixtures artifact from
    // its own main source set is safe, unlike any real release classpath (E00-18 pattern).
    implementation(testFixtures(project(":core:crypto")))
    // `SslClientFactory`'s default `SessionTicketDisabler` calls `android.net.ssl.SSLSockets`
    // (Android-only); this whole harness client runs on a bare JVM, so `JvmConscryptSessionTicketDisabler`
    // (this module's `main`) needs the real Conscrypt-JVM provider as a genuine runtime
    // dependency, not a test-only one (a deviation from the backlog's "Conscrypt-JVM test
    // dependency" phrasing — see the coder's report for E15-21).
    implementation(libs.conscrypt.openjdk.uber)

    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)

    // TestIdentity (self-test only, jvmIntegrationTest source set): SoftwareIdentityKeyStore
    // (E10-15, already on `implementation`) builds a throwaway server identity for the
    // in-process TestTlsServer; TestClock (E00-18) drives its injected Clock.
    "jvmIntegrationTestImplementation"(project(":core:testing"))
}

tasks.named<Test>("test") {
    useJUnitPlatform()
}

// Hand-rolled equivalent of the `application` plugin's `run` task (see the top-of-file note on
// why that plugin isn't applied here): `./gradlew :harness:jvm-client:run --args="--identity-file <path>"`.
// `standardInput` isn't wired to the terminal by default; the CLI is meant to be driven by
// another process (E15-15/E15-22) writing to this JVM's real stdin, so it is wired here too, for
// local/manual use.
tasks.register<JavaExec>("run") {
    group = "application"
    description = "Runs the JVM harness client CLI (E15-21)."
    mainClass.set(harnessMainClass)
    classpath = sourceSets.getByName("main").runtimeClasspath
    standardInput = System.`in`
}

// E12-13: resolves (and, via `dependsOn("classes")`, builds) this module's runtime classpath
// exactly once, so the integration script can then launch the CLI directly with plain `java`
// for each of its scenarios instead of paying a `./gradlew run` build/config cost per scenario.
tasks.register("printRuntimeClasspath") {
    group = "application"
    description = "Prints the JVM harness client's runtime classpath, one entry per line (E12-13)."
    dependsOn("classes")
    doLast {
        sourceSets.getByName("main").runtimeClasspath.files.forEach { println(it.absolutePath) }
    }
}
