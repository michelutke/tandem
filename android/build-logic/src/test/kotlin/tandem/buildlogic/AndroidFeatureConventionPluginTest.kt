package tandem.buildlogic

// tdd (E00-02): unit: androidFeaturePlugin_appliedViaGradleTestKit_setsCompileSdkAndLint

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files

class AndroidFeatureConventionPluginTest {

    @Test
    fun androidFeaturePlugin_appliedViaGradleTestKit_setsCompileSdkAndLint() {
        val projectDir = createFixtureProject()

        val result = GradleRunner.create()
            .withProjectDir(projectDir)
            .withPluginClasspath()
            .withArguments("printAndroidConfig", "-q")
            .build()

        val output = result.output.trim().lines()
        assertEquals(listOf("compileSdk=37", "lintAbortOnError=true"), output)
    }

    private fun createFixtureProject(): File {
        val projectDir = Files.createTempDirectory("tandem-android-feature-fixture").toFile()

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
            rootProject.name = "feature-fixture"
            """.trimIndent(),
        )
        File(projectDir, "build.gradle.kts").writeText(
            """
            plugins {
                id("tandem.android.feature")
            }
            android {
                namespace = "dev.tandem.fixture"
            }
            tasks.register("printAndroidConfig") {
                doLast {
                    val ext = project.extensions.getByType(com.android.build.api.dsl.LibraryExtension::class.java)
                    println("compileSdk=${'$'}{ext.compileSdk}")
                    println("lintAbortOnError=${'$'}{ext.lint.abortOnError}")
                }
            }
            """.trimIndent(),
        )
        File(projectDir, "local.properties").writeText("sdk.dir=${androidSdkDir()}\n")
        return projectDir
    }
}
