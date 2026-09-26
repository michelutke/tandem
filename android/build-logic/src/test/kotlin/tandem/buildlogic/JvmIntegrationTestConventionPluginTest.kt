package tandem.buildlogic

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files

class JvmIntegrationTestConventionPluginTest {

    // tdd (E15-21): ci: jvmIntegrationConvention_sampleFeatureModuleOptIn_compilesIntoHarnessClasspath
    @Test
    fun jvmIntegrationConvention_sampleFeatureModuleOptIn_compilesIntoHarnessClasspath() {
        val projectDir = createFixtureProject()

        val result = GradleRunner.create()
            .withProjectDir(projectDir)
            .withPluginClasspath()
            .withArguments("jvmIntegrationTest")
            .build()

        assertTrue(
            result.output.contains("BUILD SUCCESSFUL"),
            "expected the sample feature module's jvmIntegrationTest source set to compile and its " +
                "test to pass:\n${result.output}",
        )
    }

    private fun createFixtureProject(): File {
        val projectDir = Files.createTempDirectory("tandem-jvm-integration-test-fixture").toFile()

        File(projectDir, "settings.gradle.kts").writeText(
            """
            pluginManagement {
                repositories {
                    google()
                    mavenCentral()
                }
            }
            dependencyResolutionManagement {
                repositories {
                    google()
                    mavenCentral()
                }
                versionCatalogs {
                    create("libs") {
                        from(files("${realLibsVersionCatalog()}"))
                    }
                }
            }
            rootProject.name = "jvm-integration-test-fixture"
            """.trimIndent(),
        )
        // A "sample feature/*" module: pure Kotlin JVM (no `com.android.library`/AGP applied at
        // all, so it is structurally impossible for `android.jar` to be on any of its
        // configurations), the shape a later E40/E50/E51 feature-domain module opting into
        // `jvmIntegrationTest` will have.
        File(projectDir, "build.gradle.kts").writeText(
            """
            plugins {
                id("tandem.jvm-integration-test")
            }
            """.trimIndent(),
        )

        val mainSourceDir = File(projectDir, "src/main/kotlin").apply { mkdirs() }
        File(mainSourceDir, "SampleDomainLogic.kt").writeText(
            """
            class SampleDomainLogic {
                fun greeting(): String = "hello from the sample feature module's main source set"
            }
            """.trimIndent(),
        )

        val jvmIntegrationTestSourceDir = File(projectDir, "src/jvmIntegrationTest/kotlin").apply { mkdirs() }
        File(jvmIntegrationTestSourceDir, "SampleDomainLogicIntegrationTest.kt").writeText(
            """
            import org.junit.jupiter.api.Assertions.assertEquals
            import org.junit.jupiter.api.Test

            class SampleDomainLogicIntegrationTest {

                @Test
                fun sampleDomainLogic_greeting_returnsExpectedString() {
                    assertEquals(
                        "hello from the sample feature module's main source set",
                        SampleDomainLogic().greeting(),
                    )
                }
            }
            """.trimIndent(),
        )

        return projectDir
    }
}
