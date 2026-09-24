import com.android.build.api.dsl.LibraryExtension

plugins {
    id("tandem.android.library")
}

// Feature modules never depend on each other (PRD structural-decomposition > Module rules;
// enforced by E00-14); this convention plugin is the single place that changes if that rule
// needs stricter lint in the future.
extensions.configure<LibraryExtension> {
    lint {
        abortOnError = true
        warningsAsErrors = true
    }
}
