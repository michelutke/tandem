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
    ":core:discovery",
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
    ":feature:pairing",
    ":feature:status",
    ":lint:detekt-rules",
    ":companion-app",
)

// E00-22: the companion notification-poster app lives under tools/, not android/, so its own
// README (E00-01) and the directory-manifest check both see it as a `tools/*` leaf; it is
// otherwise a plain module of this build, reusing the version catalog and quality convention
// plugins like every other module. check_gradle_projects.rb maps this path back explicitly.
project(":companion-app").projectDir = file("../tools/companion-app")
