// E00-29: standalone fixture project (its own settings.gradle.kts) used by
// tools/lint/test/gradle_dependency_verification_test.sh to exercise Gradle's dependency
// verification against a throwaway local Maven repository, without touching the real
// android/gradle/verification-metadata.xml.
repositories {
    maven { url = uri("repo") }
}

val fixtureVersion: String = providers.gradleProperty("fixtureVersion").getOrElse("0.0.0")

val fixture by configurations.creating

dependencies {
    add("fixture", "dev.tandem.fixture:verify-target:$fixtureVersion")
}

tasks.register("resolveFixture") {
    doLast {
        configurations["fixture"].files.forEach { println(it) }
    }
}
