// Root build file. Module build files apply a convention plugin from build-logic instead of
// repeating plugin/version boilerplate; see build-logic/src/main/kotlin/tandem.*.gradle.kts.
// `android/app` is the one module that applies AGP/Kotlin directly (see app/build.gradle.kts);
// these `apply false` declarations resolve their versions from the version catalog once for
// the whole build.
// `tandem.module-rules` (E00-14) inspects the whole project graph, so it is applied here rather
// than by each module's own build script.
// Kover (E00-06) is applied at root for aggregate coverage reporting.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kover)
    id("tandem.module-rules")
}

// E00-29: freeze every module's resolved dependency graph; `gradle.lockfile` per project is
// regenerated with `./gradlew <task> --write-locks` and reviewed like any other checked-in file.
subprojects {
    dependencyLocking {
        lockAllConfigurations()
    }
}

// E00-06: Kover aggregate coverage report across all modules. The koverHtmlReport task generates
// an HTML report in build/reports/kover/html/ that includes all modules' coverage metrics.
kover {
    reports {
        total {
            html.title = "Tandem Coverage Report"
        }
    }
}
