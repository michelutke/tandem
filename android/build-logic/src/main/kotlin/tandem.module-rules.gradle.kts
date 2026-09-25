import org.gradle.api.GradleException
import org.gradle.api.artifacts.ExternalDependency
import org.gradle.api.artifacts.ProjectDependency

// E00-14: module dependency rules that need the whole project graph, not a single module's own
// build script: `feature/*` modules never depend on each other, and no module may depend on an
// artifact from the denylist shared with the macOS rule (tools/lint/dependency-denylist.txt;
// invariant 2 and the cycle-4 no-third-party-crash-SDK decision). Applied once, on the root
// project, by android/build.gradle.kts.

val denylist: List<String> =
    rootDir.resolve("../tools/lint/dependency-denylist.txt").let { file ->
        if (!file.exists()) {
            emptyList()
        } else {
            file.readLines()
                .map { it.trim() }
                .filter { it.isNotEmpty() && !it.startsWith("#") }
                .map { it.lowercase() }
        }
    }

val verifyModuleRules = tasks.register("verifyModuleRules") {
    group = "verification"
    description = "Fails if a feature module depends on another feature module, or any module " +
        "depends on a denylisted artifact (E00-14)."

    doLast {
        val errors = mutableListOf<String>()

        allprojects.forEach { proj ->
            proj.configurations.forEach { configuration ->
                configuration.dependencies.forEach { dependency ->
                    when (dependency) {
                        is ProjectDependency -> {
                            val targetPath = dependency.path
                            if (proj.path.startsWith(":feature:") &&
                                targetPath.startsWith(":feature:") &&
                                targetPath != proj.path
                            ) {
                                errors +=
                                    "${proj.path}: feature module depends on feature module $targetPath " +
                                        "(features must depend only on core modules, never on each other)"
                            }
                        }
                        is ExternalDependency -> {
                            val identity = "${dependency.group}:${dependency.name}".lowercase()
                            denylist.forEach { bad ->
                                if (identity.contains(bad)) {
                                    errors +=
                                        "${proj.path}: dependency '${dependency.group}:${dependency.name}' " +
                                            "matches denylisted pattern '$bad'"
                                }
                            }

                            // E00-29: no dynamic versions ("+" ranges or "latest.*"); every
                            // resolved version must be exact so verification-metadata.xml and
                            // dependency locking pin a single, reviewable artifact.
                            val version = dependency.version
                            if (version != null && (version.contains('+') || version.startsWith("latest."))) {
                                errors +=
                                    "${proj.path}: dependency '${dependency.group}:${dependency.name}' " +
                                        "uses dynamic version '$version' (exact versions only)"
                            }
                        }
                    }
                }
            }
        }

        if (errors.isNotEmpty()) {
            throw GradleException("verifyModuleRules failed:\n" + errors.distinct().joinToString("\n") { "  $it" })
        }
    }
}

subprojects {
    tasks.matching { it.name == "check" }.configureEach {
        dependsOn(verifyModuleRules)
    }
}
