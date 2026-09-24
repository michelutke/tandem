package tandem.buildlogic

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files

class AndroidTestFixturesConventionPluginTest {

    // tdd (E00-04): unit: sampleFlowEmitter_collectedWithTurbine_emitsOneTwoThreeThenCompletes
    @Test
    fun sampleFlowEmitter_collectedWithTurbine_emitsOneTwoThreeThenCompletes() {
        val projectDir = createFixtureProject()

        val result = GradleRunner.create()
            .withProjectDir(projectDir)
            .withPluginClasspath()
            .withArguments("test")
            .build()

        assertTrue(
            result.output.contains("BUILD SUCCESSFUL"),
            "expected the sample Turbine flow test to run and pass:\n${result.output}",
        )
    }

    // tdd (E00-04): ci: gradleTest_sampleModule_junitXmlWrittenToBuildTestResults
    @Test
    fun gradleTest_sampleModule_junitXmlWrittenToBuildTestResults() {
        val projectDir = createFixtureProject()

        GradleRunner.create()
            .withProjectDir(projectDir)
            .withPluginClasspath()
            .withArguments("test")
            .build()

        val reportDir = File(projectDir, "build/test-results/testDebugUnitTest")
        val reportFiles = reportDir.listFiles { file -> file.name.endsWith(".xml") }.orEmpty()

        assertTrue(
            reportFiles.isNotEmpty(),
            "expected a JUnit XML report under ${reportDir.path}, found: ${reportDir.list()?.toList()}",
        )
        assertTrue(
            reportFiles.any { it.readText().contains("sampleFlowEmitter_collectedWithTurbine_emitsOneTwoThreeThenCompletes") },
            "expected the sample test name in the JUnit XML report",
        )
    }

    private fun createFixtureProject(): File {
        val projectDir = Files.createTempDirectory("tandem-android-test-fixtures-fixture").toFile()

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
            rootProject.name = "test-fixtures-fixture"
            """.trimIndent(),
        )
        File(projectDir, "build.gradle.kts").writeText(
            """
            plugins {
                id("tandem.android.library")
            }
            android {
                namespace = "dev.tandem.fixture"
            }
            """.trimIndent(),
        )
        File(projectDir, "local.properties").writeText("sdk.dir=${androidSdkDir()}\n")

        val testSourceDir = File(projectDir, "src/test/kotlin").apply { mkdirs() }
        File(testSourceDir, "SampleFlowEmitterTest.kt").writeText(
            """
            import app.cash.turbine.test
            import kotlinx.coroutines.flow.flowOf
            import kotlinx.coroutines.test.runTest
            import org.junit.jupiter.api.Assertions.assertEquals
            import org.junit.jupiter.api.Test

            class SampleFlowEmitterTest {

                @Test
                fun sampleFlowEmitter_collectedWithTurbine_emitsOneTwoThreeThenCompletes() = runTest {
                    flowOf(1, 2, 3).test {
                        assertEquals(1, awaitItem())
                        assertEquals(2, awaitItem())
                        assertEquals(3, awaitItem())
                        awaitComplete()
                    }
                }
            }
            """.trimIndent(),
        )

        return projectDir
    }
}
