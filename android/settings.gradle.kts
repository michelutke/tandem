pluginManagement {
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "tandem-android"

include(
    ":app",
    ":core:crypto",
    ":core:pairing",
    ":core:protocol",
    ":core:storage",
    ":core:testing",
    ":core:transport",
    ":feature:calls",
    ":feature:clipboard",
    ":feature:files",
    ":feature:input",
    ":feature:messaging",
    ":feature:mirror",
    ":feature:notifications",
    ":lint:detekt-rules",
)
