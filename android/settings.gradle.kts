// E00-29: `google()` is restricted to the groups it actually publishes (androidx / com.android /
// com.google); everything else resolves from mavenCentral. Narrows the supply-chain surface of
// each repository to what it is expected to serve.
pluginManagement {
    includeBuild("build-logic")
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "tandem-android"

include(
    ":app",
    ":harness:jvm-client",
    ":core:crypto",
    ":core:designsystem",
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
