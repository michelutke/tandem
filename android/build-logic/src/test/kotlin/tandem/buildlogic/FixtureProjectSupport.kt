package tandem.buildlogic

import java.io.File

// Shared helpers for GradleTestKit fixture projects created by the convention-plugin tests in
// this package: the fixture is a standalone temp project, so it needs to be pointed at the real
// Android SDK and at the real `libs` version catalog explicitly.

internal fun androidSdkDir(): String {
    System.getenv("ANDROID_SDK_ROOT")?.let { return it }
    System.getenv("ANDROID_HOME")?.let { return it }
    val androidProjectDir = File(System.getProperty("tandem.androidProjectDir"))
    return File(androidProjectDir, "local.properties")
        .readLines()
        .first { it.startsWith("sdk.dir=") }
        .substringAfter("sdk.dir=")
}

internal fun realLibsVersionCatalog(): String {
    val androidProjectDir = File(System.getProperty("tandem.androidProjectDir"))
    return File(androidProjectDir, "gradle/libs.versions.toml").absolutePath.replace("\\", "\\\\")
}
