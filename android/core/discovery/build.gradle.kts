plugins {
    id("tandem.android.instrumented")
    id("tandem.android.hilt")
}

android {
    namespace = "dev.tandem.core.discovery"

    // FakeServiceDiscovery (E21-04) lives here so downstream modules (E21-05, E20-06) consume it
    // via testFixtures, never a release classpath (E00-18 pattern).
    testFixtures {
        enable = true
    }
}

dependencies {
    // ServiceDiscovery/NsdServiceDiscovery expose Flow/CoroutineDispatcher in their own public API
    // (E21-04), so this is api(), not implementation() -- mirrors core/protocol's own
    // api(libs.kotlinx.coroutines.core).
    api(libs.kotlinx.coroutines.core)
}
