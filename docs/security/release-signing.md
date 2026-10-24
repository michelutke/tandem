# Release build signing (E71-11)

Signed release artifacts for both platforms come from `.github/workflows/release.yml`, which runs
only on pushed `v*` tags and builds with the same Gradle and `xcodebuild` commands as `android.yml`
and `macos.yml`. Every artifact is verified by `tools/release-audit/verify-release-signing.rb`
before upload. Decision: D-82 (`docs/planning/decisions.md`).

## Decision

| Platform | Signing | Why |
|---|---|---|
| Android | APK Signature Scheme v2 + v3 with a dedicated release key (v1 JAR signing off: minSdk 33). Sideload distribution, no Play App Signing. | The PRD excludes store distribution. The key is the app's update identity: Android refuses to install an update signed with another key, so a lost key means reinstalling, and a leaked key lets anyone ship "updates". The debug key is public and is never accepted. |
| macOS | Developer ID Application certificate with hardened runtime when `MACOS_DEVELOPER_ID_P12_BASE64` is set; otherwise ad hoc (`-`). Notarization optional, on when the `MACOS_NOTARIZE` variable is `true`. | No Mac App Store (PRD non-goal). Developer ID keeps Gatekeeper's identified-developer check and a stable designated requirement for keychain access across updates; ad hoc is the documented fallback for local builds. Notarization adds no security property Tandem relies on, so it stays optional. |

`android/app/build.gradle.kts` reads the keystore only from `TANDEM_RELEASE_KEYSTORE*` environment
variables. When they are absent the release APK is left unsigned, which fails verification; there is
no fallback to the debug key.

## Verification

| Check | Fails when | Test |
|---|---|---|
| `apksigner verify --print-certs` | unsigned or tampered APK | `releaseSigningCheck_unsignedApk_apksignerVerifyFails` |
| signer DN is not `CN=Android Debug` | debug-key-signed APK | `releaseSigningCheck_apkSignedWithDebugKey_exitsNonZero` |
| signer SHA-256 equals the `ANDROID_RELEASE_CERT_SHA256` variable (when set) | APK signed with any other key | `releaseSigningCheck_expectedCertDigestMismatch_exitsNonZero` |
| `codesign --verify --deep --strict` | unsigned or tampered `.app` | `releaseSigningCheck_tamperedMacApp_codesignVerifyFails` |
| `xcrun stapler validate` (notarization on) | no stapled ticket | `releaseSigningCheck_notarizationEnabledWithoutTicket_staplerValidateFails` |
| `tools/ci/check_release_signing_secrets.rb` | a non-tag workflow, or a job outside the `release` environment, reads a signing secret or passes `secrets: inherit` | `releaseSigningSecrets_pullRequestWorkflow_notAvailable` |

The checker's decisions are unit-tested with stub tools (`tools/release-audit/test/release_signing_test.rb`,
every PR via `repo-checks`). The real tools run against real artifacts on every Android and macOS
PR: `android_release_signing_test.sh` (unsigned release APK, debug APK, throwaway-key-signed APK)
and `macos_release_signing_test.sh` (unsigned, ad hoc signed, tampered, and unstapled `.app`).

## Secrets and the `release` environment

Secrets are stored in the GitHub environment `release`, never as repository secrets, so only jobs
that declare `environment: release` can read them. Pull-request workflows cannot: they do not name
the environment (enforced by `check_release_signing_secrets.rb`), and fork PRs receive no secrets
at all.

| Name | Kind | Used for |
|---|---|---|
| `ANDROID_RELEASE_KEYSTORE_BASE64` | secret | base64 of the release keystore (PKCS12) |
| `ANDROID_RELEASE_KEYSTORE_PASSWORD`, `ANDROID_RELEASE_KEY_ALIAS`, `ANDROID_RELEASE_KEY_PASSWORD` | secret | keystore access |
| `ANDROID_RELEASE_CERT_SHA256` | variable | expected signer digest (pins the release key) |
| `MACOS_DEVELOPER_ID_P12_BASE64`, `MACOS_DEVELOPER_ID_P12_PASSWORD` | secret | Developer ID Application certificate and key |
| `MACOS_NOTARIZE` | variable | `true` enables notarization and the stapler check |
| `MACOS_NOTARY_APPLE_ID`, `MACOS_NOTARY_TEAM_ID`, `MACOS_NOTARY_PASSWORD` | secret | `notarytool` credentials (app-specific password) |

Owner setup (repository settings; not expressible in code):

1. Settings → Environments → New environment `release`.
2. Required reviewers: the owner. Prevent self-review off (single-owner repo).
3. Deployment branches and tags: "Selected branches and tags", add tag rule `v*`.
4. Settings → Rules → Rulesets: protect tags `v*` (restrict creation, update and deletion to the
   owner).
5. Add the secrets and variables above to the `release` environment.

## Key handling

- Create the Android key once, offline: `keytool -genkeypair -keystore tandem-release.p12
  -storetype PKCS12 -alias tandem -keyalg EC -groupname secp256r1 -validity 10000`. Keep an offline
  backup; record its SHA-256 in `ANDROID_RELEASE_CERT_SHA256`.
- The workflow writes the keystore and `.p12` to `$RUNNER_TEMP` with mode 0600, and removes them
  (and the temporary keychain) in `if: always()` steps.
- Rotating the Android key needs APK Signature Scheme v3 key rotation (`apksigner rotate`) so
  installed apps accept the update; plan it as its own change.
