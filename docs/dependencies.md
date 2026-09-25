# Third-party dependency register (E00-29)

Every direct dependency — every `[libraries]` entry in `android/gradle/libs.versions.toml` and
every `.package(url:)` in a `macos/Packages/*/Package.swift` — needs a row below with an allowed
license and the issue that introduced it. `tools/lint/dependency_registry.rb` enforces this in CI
(`repo-checks.yml`): a new direct dependency without a row, or a row whose license isn't allowed,
fails the build naming it.

Transitive dependencies are covered by `android/gradle/verification-metadata.xml` (checksums) and
each Swift package's `Package.resolved` (pins); they don't need a row here. The release SBOM and
CVE scan are E71-10.

Allowed licenses: **Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, ISC, Zlib, EPL-2.0, EPL-1.0**.
EPL-2.0 and EPL-1.0 are added beyond D-32's literal list for pre-existing, test-only JUnit
dependencies: EPL-2.0 for JUnit 5 (Jupiter + Vintage) — the test framework the top-level
`CLAUDE.md` testing section mandates (`unit — JUnit5 + Turbine`) — and EPL-1.0 for JUnit 4, which
arrives transitively required by Robolectric (E00-20) and `androidx.test` (E00-21), both of which
still run on the JUnit 4 runner. Both are weak-copyleft (not GPL/AGPL/LGPL/SSPL) and never ship
(test-scope only). See the coder's report for E00-29 for the full reasoning; flagged here as a
deviation from the literal decision text, not a silent substitution.

Anything else — GPL, AGPL, LGPL, SSPL, or a license this file doesn't name — fails the gate.

## Android (`android/gradle/libs.versions.toml`)

| Dependency | License | Purpose | Issue |
|---|---|---|---|
| `com.android.tools.build:gradle` | Apache-2.0 | Android Gradle Plugin | E00-04 |
| `org.jetbrains.kotlin:kotlin-gradle-plugin` | Apache-2.0 | Kotlin compiler/Gradle integration | E00-04 |
| `org.junit.jupiter:junit-jupiter` | EPL-2.0 | Unit test framework (`unit` layer, CLAUDE.md) | E00-05 |
| `org.junit.platform:junit-platform-launcher` | EPL-2.0 | JUnit Platform test launcher | E00-05 |
| `app.cash.turbine:turbine` | Apache-2.0 | Kotlin Flow testing (`unit` layer, CLAUDE.md) | E00-05 |
| `org.jetbrains.kotlinx:kotlinx-coroutines-test` | Apache-2.0 | Coroutine test dispatchers | E00-05 |
| `org.jetbrains.kotlinx:kotlinx-coroutines-core` | Apache-2.0 | `Flow`/`Mutex`/`Channel`/`Deferred` for `ChannelMultiplexer` and the settings store's writer scope | E11-05, E13-04 |
| `org.jetbrains.kotlinx:kotlinx-serialization-json` | Apache-2.0 | Test-only: parse `protocol/vectors` JSON in frame codec tests | E11-01 |
| `androidx.activity:activity` | Apache-2.0 | `ComponentActivity` base for `TandemActivity` (tapjacking filter) | E00-28 |
| `com.google.devtools.ksp:symbol-processing-gradle-plugin` | Apache-2.0 | KSP annotation processing for Hilt (kapt unsupported with AGP 9 built-in Kotlin) | E00-03 |
| `com.google.dagger:hilt-android-gradle-plugin` | Apache-2.0 | Hilt Gradle plugin (bytecode transform, aggregation) | E00-03 |
| `com.google.dagger:hilt-android` | Apache-2.0 | Hilt dependency injection runtime | E00-03 |
| `com.google.dagger:hilt-compiler` | Apache-2.0 | Hilt/Dagger code generator (KSP, build-time only) | E00-03 |
| `androidx.activity:activity-compose` | Apache-2.0 | `setContent` for Compose activities | E00-03 |
| `androidx.test:core` | Apache-2.0 | Test-only: `ActivityScenario`/`ApplicationProvider` in instrumented tests | E00-03 |
| `com.google.protobuf:protobuf-javalite` | BSD-3-Clause | Protobuf runtime (Java, lite) | E00-09 |
| `com.google.protobuf:protobuf-kotlin-lite` | BSD-3-Clause | Protobuf runtime (Kotlin, lite) | E00-09 |
| `org.jlleitschuh.gradle:ktlint-gradle` | MIT | Kotlin formatting gate | E00-05 |
| `io.gitlab.arturbosch.detekt:detekt-gradle-plugin` | Apache-2.0 | Static analysis gate | E00-05 |
| `io.gitlab.arturbosch.detekt:detekt-api` | Apache-2.0 | Custom detekt rules (`:lint:detekt-rules`) | E00-14 |
| `io.gitlab.arturbosch.detekt:detekt-test` | Apache-2.0 | Detekt rule unit-test fixtures (`:lint:detekt-rules`) | E00-17 |
| `androidx.test:runner` | Apache-2.0 | Instrumented test runner (Gradle Managed Devices) | E00-21 |
| `androidx.test.espresso:espresso-core` | Apache-2.0 | Instrumented UI test actions/assertions | E00-21 |
| `androidx.test.ext:junit` | Apache-2.0 | JUnit4 rules/runners for instrumented tests | E00-21 |
| `junit:junit` | EPL-1.0 | JUnit 4 runner required by Robolectric/`androidx.test` | E00-20 |
| `org.junit.vintage:junit-vintage-engine` | EPL-2.0 | Runs JUnit 4 tests on the JUnit 5 platform | E00-20 |
| `org.robolectric:robolectric` | MIT | Android-framework unit tests on the JVM (`unit` layer, CLAUDE.md) | E00-20 |
| `org.jetbrains.kotlin:compose-compiler-gradle-plugin` | Apache-2.0 | Jetpack Compose compiler plugin | E00-20 |
| `androidx.compose:compose-bom` | Apache-2.0 | Compose version alignment (bill of materials) | E00-20 |
| `androidx.compose.material3:material3` | Apache-2.0 | Compose Material 3 components | E00-20 |
| `androidx.compose.ui:ui-tooling-preview` | Apache-2.0 | `@Preview` annotations for design-system components | E00-31 |
| `androidx.compose.ui:ui-tooling` | Apache-2.0 | Debug-only preview rendering for design-system components | E00-31 |
| `androidx.compose.ui:ui-test-junit4` | Apache-2.0 | Compose UI test rule (JUnit4-based) | E00-20 |
| `androidx.compose.ui:ui-test-manifest` | Apache-2.0 | Compose UI test manifest activity | E00-20 |
| `com.code-intelligence:jazzer-junit` | Apache-2.0 | Jazzer JUnit fuzz target for FrameDecoder/Envelope (frame/envelope parser fuzzing, E15-13) | E15-13 |
| `androidx.datastore:datastore-preferences-core` | Apache-2.0 | Preferences DataStore engine for the settings store; pure Kotlin/JVM artifact, no Robolectric needed | E13-04 |

`jazzer-junit` pulls in `com.code-intelligence:jazzer` and `com.code-intelligence:jazzer-api`
transitively (both Apache-2.0, both left un-pinned in `[libraries]` since only `jazzer-junit` is a
direct dependency here — see the license-gate rule above). Checked
`https://repo1.maven.org/maven2/com/code-intelligence/jazzer/0.30.0/`: unlike `aapt2`, Jazzer
publishes a single universal `jazzer-0.30.0.jar` per artifact/version (no `-linux`/`-windows`/`-osx`
classifiers — it bundles its native libFuzzer/JVM-agent pieces as resources inside that one jar).
So a normal `--write-verification-metadata` regeneration (even run on macOS) records one entry per
artifact that's valid regardless of the CI runner's OS; no aapt2-style hand-added per-OS checksum
entries were needed or added for Jazzer.

## macOS / Swift (`macos/Packages/*/Package.swift`)

| Dependency | License | Purpose | Issue |
|---|---|---|---|
| `swift-protobuf` | Apache-2.0 | Protobuf runtime for `TandemProtocol` | E00-09 |
| `swift-certificates` | Apache-2.0 | Self-signed leaf certificate generation (`X509`) over the Keychain identity key | E10-06 |

## Update bot

Dependabot (not Renovate): it's built into GitHub with no separate app install or hosted service,
and natively covers all three ecosystems this repo needs — `gradle`, `swift` (standalone SwiftPM
packages with a `Package.swift`) and `github-actions` — from one YAML file
(`.github/dependabot.yml`). Renovate is more configurable, but that configurability (regex
managers, custom datasources) isn't needed here and would mean either a hosted GitHub App or
self-hosting a runner; Dependabot keeps the whole update path inside GitHub's own trust boundary,
which matches "no new supply-chain surface" better than the alternative. Weekly, grouped by
ecosystem, per D-32. A grouped update PR still has to pass the same CI as any other change
(verification metadata, locks, `Package.resolved`, license gate, pinned-actions check), so a bump
that fails any of them doesn't merge silently.

## Regenerating verification metadata and lockfiles

`android/gradle/verification-metadata.xml` and each module's `gradle.lockfile` are generated, not
hand-edited. Regenerate both after adding/upgrading a Gradle dependency, or after another branch
merges one (several were in flight concurrently with E00-29: detekt-test, Robolectric/Compose,
androidx.test):

```sh
cd android
./gradlew --write-verification-metadata sha256 help build ktlintCheck detekt :app:assembleDebug test
./gradlew build ktlintCheck detekt --write-locks
```

Platform-classified artifacts resolve only for the host OS, so a macOS regeneration records only
the `-osx` variant. `aapt2` is the known case: CI runs on Linux, so its `-linux` (and `-windows`)
jar checksums are added by hand from Google Maven with the published `.sha1` cross-checked. After
an AGP upgrade, add the new version's `-linux`/`-windows` entries the same way or CI fails
verification.

Review the diff to both `gradle/verification-metadata.xml` and every changed `gradle.lockfile`
before committing — that diff is the actual code review for a new/updated dependency. Then add its
row to this file (Android section above) with its license and issue ID.

`--write-locks` re-resolves ignoring the existing locks; a couple of ktlint-gradle's own reporter
tool dependencies (`io.github.detekt.sarif4k`, `io.github.oshai:kotlin-logging-jvm`) were observed
resolving to a different version on a bare re-resolve than what was already locked, with no build
file changes in between. If a regen run's diff moves one of those two backwards/sideways for no
reason you changed, re-run `--write-locks` once more and diff again before trusting either result;
don't hand-edit the lockfile to "fix" it.

Swift has no equivalent regeneration step: each `macos/Packages/*/Package.resolved` updates via
`swift package update` (or Xcode's "Update to Latest Package Versions") in the normal course of
adding/upgrading a Swift dependency, and CI (`macos.yml`) fails if that would still change the
checked-in file (`--only-use-versions-from-resolved-file`).
