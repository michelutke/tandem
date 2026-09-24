# Tandem backlog (generated — edit `backlog/*.yaml`, run `sync_issues.rb render`)

## Phase 0 — Foundations

### E00 — Monorepo scaffolding and CI

Stand up the monorepo exactly as PRD `<structural-decomposition>` lays it out, with a working Gradle
build, a working Xcode/SwiftPM build, generated-code hygiene, CI on both platforms with path
filters, and the repo-level guardrails (CLAUDE.md, module dependency rules, secret scanning,
release-log lint, test seams and harnesses, Android platform hardening, supply-chain controls and a
release test-code scan) that every later epic relies on. Nothing here implements a PRD feature; it
makes every later issue buildable, testable, and reviewable. Review cycle 5: infrastructure first
needed later stays in this epic (IDs are epic-bound) but is marked `lands_in_phase` and lands at the
start of that phase: E00-26, E00-29, E00-30 (Phase 1), E00-28 (Phase 2), E00-22 (Phase 3). Phase 0
exit does not wait for them.

**Exit criteria**

- [ ] Fresh checkout builds on ubuntu-latest (`./gradlew help`) and on a macos runner (`xcodebuild -list`).
- [ ] CI runs android, macos, protocol, and conformance jobs, each triggered only by its path filter.
- [ ] Editing a generated `*.pb.kt` or `*.pb.swift` file by hand fails CI.
- [ ] A feature module depending on another feature module fails the build.
- [ ] A non-transport module opening a raw socket fails the build.
- [ ] `CLAUDE.md` exists at repo root and contains the eight security invariants verbatim.
- [ ] `CLAUDE.md` has a testing section listing the eight tdd layer prefixes and the seam rule (inject Clock/dispatchers/ByteStream/KeyStore/Keychain; no `System.currentTimeMillis()`/`Date()` in core).
- [ ] `android/core/testing` (TestClock, FakeElapsedRealtime, InMemoryDuplexPipe) and `macos/Packages/TandemTestSupport` (ManualTestClock, InMemoryConnectionPair) exist; neither is on a release classpath/link map.
- [ ] Robolectric + Compose `ui:` tests run in the ubuntu `android` job with no emulator; the `android-instrumented` emulator job (API 29 + 35) is a required check on `android/**` PRs.
- [ ] Phase 3 start (E00-22): `tools/companion-app` builds in CI and is installed on the managed devices before instrumented tests run.
- [ ] Phase 1 start (E00-26): `TandemUITests` XCUITest target runs on the macOS runner; Release binary contains no `UITestScenario` string.
- [ ] Phase 1 start (E00-29, E00-30): supply-chain checks fail on a changed artifact checksum, a + version, a tag-referenced action, a changed Package.resolved, a GPL-3.0 dependency or one missing from docs/dependencies.md; the release test-code scan fails on fixtures containing SoftwareIdentityKeyStore, ManualTestClock or an extra executable in Tandem.app and passes on the current release build.
- [ ] Phase 2 start (E00-28): the Android hardening check fails on fixtures with allowBackup=true, user trust anchors, a non-allowlisted export, a mutable or implicit PendingIntent, or QUERY_ALL_PACKAGES.
- [ ] `docs/testing/device-matrix.md` and `docs/testing/manual-gates.md` exist; the CI check that every `manual:` tdd entry has a matching manual-gates heading passes.
- [ ] Adding an HTTP-server or third-party crash/analytics SDK dependency fails the build on both platforms (E00-14, E00-15).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E00-01 | [docs] Create monorepo directory skeleton per PRD structural decomposition | task | P0 | S |  |
| E00-02 | [android] Gradle multi-module skeleton, convention plugins, version catalog | task | P0 | M | E00-01 |
| E00-03 | [android] Hilt DI wiring skeleton across modules | task | P0 | S | E00-02, E00-04, E00-21 |
| E00-04 | [android] JUnit5 + Turbine test infrastructure baseline | task | P0 | S | E00-02 |
| E00-05 | [android] ktlint + detekt baseline configuration | task | P0 | S | E00-02 |
| E00-06 | [android] Kover/Jacoco coverage reporting setup | task | P1 | S | E00-02, E00-04 |
| E00-07 | [macos] Xcode project + local SwiftPM package skeleton (Swift 6 strict concurrency) | task | P0 | M | E00-01 |
| E00-08 | [macos] Swift Testing baseline + SwiftLint configuration | task | P0 | S | E00-07 |
| E00-09 | [protocol] buf setup + codegen for protobuf-kotlin-lite and swift-protobuf | task | P0 | M | E00-01, E00-02, E00-07 |
| E00-10 | [ci] CI check: generated protocol code is never hand-edited | task | P0 | S | E00-09 |
| E00-11 | [ci] GitHub Actions workflows with path filters (android/macos/protocol/conformance) | task | P0 | M | E00-02, E00-07, E00-09 |
| E00-12 | [docs] CLAUDE.md per PRD Appendix D including security invariants | doc | P0 | S | E00-01, E00-02, E00-07, E00-08, E00-09 |
| E00-13 | [docs] PR template, CODEOWNERS-lite, issue templates | doc | P1 | S | E00-01 |
| E00-14 | [android] Module rules: no feature-to-feature deps; only core/transport opens sockets | task | P0 | M | E00-02, E00-05 |
| E00-15 | [macos] Swift package graph dependency rule check | task | P0 | M | E00-07, E00-08 |
| E00-16 | [ci] Secret scanning setup | task | P0 | S | E00-01 |
| E00-17 | [android] Release-log lint + shared sensitive-symbol list | task | P0 | M | E00-05 |
| E00-27 | [macos] Release-log lint rule: no content logging in release builds | task | P0 | S | E00-08, E00-17 |
| E00-18 | [android] core/testing fixtures: injectable Clock, TestClock, dispatcher rules | task | P0 | M | E00-04, E00-05 |
| E00-19 | [android] In-memory duplex byte pipe for codec/transport tests | task | P0 | S | E00-18 |
| E00-20 | [android] Robolectric + Compose UI test setup on the JVM | task | P0 | M | E00-04 |
| E00-21 | [ci] Android emulator instrumented-test job (Gradle Managed Devices) | task | P0 | M | E00-04, E00-11 |
| E00-22 | [tools] Companion test app (tools/companion-app): scripted notification poster *(lands Phase 3)* | task | P0 | M | E00-02, E00-21 |
| E00-23 | [docs] Physical device matrix and manual-gate procedure | doc | P0 | S |  |
| E00-24 | [macos] TandemTestSupport package: injectable Clock and ManualTestClock | task | P0 | M | E00-07, E00-08 |
| E00-25 | [macos] ByteStreamConnection seam + InMemoryConnectionPair | task | P0 | S | E00-24 |
| E00-26 | [macos] XCUITest target with DEBUG-only scenario seeding *(lands Phase 1)* | task | P0 | M | E00-07, E00-08, E00-24 |
| E00-28 | [android] Platform-hardening baseline: backup, NSC, exports, PendingIntents, tapjacking *(lands Phase 2)* | task | P0 | M | E00-02, E00-05, E00-20 |
| E00-29 | [ci] Supply-chain baseline: dependency verification, lockfiles, pinned actions, licenses *(lands Phase 1)* | task | P0 | M | E00-02, E00-07, E00-11 |
| E00-30 | [ci] Release-artifact test-code scan (dex, Mach-O symbols, bundle contents) *(lands Phase 1)* | task | P0 | M | E00-02, E00-07, E00-11 |
| E00-31 | [android] Swiss/M3 Expressive design system: tokens, type, core components *(lands Phase 1)* | task | P0 | L | E00-04, E00-20 |
| E00-32 | [macos] Swiss/Liquid Glass design system: tokens, type, core components *(lands Phase 1)* | task | P0 | L | E00-08, E00-26 |

### E01 — Wire protocol: SPEC.md, .proto schema, test vectors

Produce the single normative source of truth for the wire protocol: `docs/protocol/SPEC.md`
(RFC 2119 language, one issue per section), the phase-0 `.proto` schemas it describes, buf
lint/breaking enforcement, and the cross-platform test-vector suite that later epics
(E10-E14) implement against and E15 runs in CI. Nothing here writes Kotlin or Swift codec
implementations; it defines what those implementations must do and proves it with vectors.

**Exit criteria**

- [ ] `buf lint` and `buf breaking --against '.git#branch=main'` both pass on `protocol/`.
- [ ] Every SPEC.md section referenced above exists, uses RFC 2119 keywords, and is cross-linked from the relevant `.proto` file's comments.
- [ ] All six vector categories (SPKI fingerprint, pairing proof + confirmation code, frames, rotating ID, QR payload, display strings) exist under protocol/vectors/, are regenerable from the reference generator, and have been reviewed (PR approval recorded).
- [ ] The E01-22 section states every timeout, connection cap and feature cap as a MUST with its close code or typed error and implementing issue.
- [ ] The channel-binding derivation in E01-01 / E01-02 matches the E03-04 outcome (exporter or in-band challenge fallback).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E01-01 | [docs] SPEC.md section: handshake & TLS profile | doc | P0 | M | E03-04 |
| E01-02 | [docs] SPEC.md section: pairing | doc | P0 | M | E03-04 |
| E01-03 | [docs] SPEC.md section: framing + envelope | doc | P0 | M |  |
| E01-04 | [docs] SPEC.md section: channels + flow control credits | doc | P0 | M |  |
| E01-05 | [docs] SPEC.md section: errors + close codes | doc | P0 | S |  |
| E01-06 | [docs] SPEC.md section: versioning & capability negotiation | doc | P0 | S |  |
| E01-07 | [docs] SPEC.md section: heartbeat | doc | P0 | S |  |
| E01-08 | [docs] SPEC.md section: discovery TXT record | doc | P0 | S |  |
| E01-09 | [docs] SPEC.md section: media ticket | doc | P0 | S |  |
| E01-10 | [protocol] envelope.proto: Envelope message with channel/seq/ack oneof | task | P0 | M | E01-03 |
| E01-11 | [protocol] pairing.proto: PairRequest / PairAccepted / PairRejected / Revoke | task | P0 | M | E01-02, E03-04 |
| E01-12 | [protocol] control.proto: heartbeat, capability negotiation, media ticket issuance | task | P0 | M | E01-06, E01-07, E01-09 |
| E01-13 | [protocol] status.proto: device status and ring messages | task | P0 | S | E01-03 |
| E01-14 | [protocol] Proto placeholder plan for later-phase domains | doc | P0 | S | E01-10 |
| E01-15 | [protocol] buf.yaml lint rules + buf breaking baseline | task | P0 | S | E01-10, E01-11, E01-12, E01-13 |
| E01-16 | [tools] Test vector file format + Python reference generator | task | P0 | M | E01-05 |
| E01-17 | [tools] Test vectors: SPKI fingerprint computation | task | P0 | S | E01-16, E01-01 |
| E01-18 | [tools] Test vectors: pairing proof HMAC | task | P0 | S | E01-16, E01-11, E01-01, E01-02 |
| E01-19 | [tools] Test vectors: frame encoding valid + invalid cases | task | P0 | M | E01-16, E01-10 |
| E01-20 | [tools] Test vectors: Bonjour rotating ID | task | P0 | S | E01-16, E01-08 |
| E01-21 | [tools] Test vectors: base64url QR payload parsing (valid + malformed) | task | P0 | S | E01-16, E01-02 |
| E01-22 | [docs] SPEC.md section: timeouts, connection limits and resource caps | doc | P0 | M | E01-01, E01-03, E01-04, E01-05 |
| E01-23 | [docs] SPEC.md section: untrusted peer strings (display sanitization) | doc | P0 | S | E01-02 |
| E01-24 | [tools] Test vectors: display-string sanitization | task | P0 | S | E01-16, E01-23 |

### E02 — Threat model and ADR-001…006

Write the STRIDE threat model for every data flow in the architecture diagram, and record
ADR-001 through ADR-006 with the options and decision criteria from the PRD architecture
section. ADR-006 (mirroring transport) is explicitly allowed to defer its final decision to
Phase 6, but Phase 0 must record the options and criteria now.

**Exit criteria**

- [ ] docs/threat-model.md covers every arrow in the PRD data-flow diagram (E02-01) and every local surface in E02-08 with STRIDE categories and at least one mitigation reference per threat; every cycle-4 decision has a row with its residual risk; AC-01..AC-20 are each referenced at least once.
- [ ] Six ADR files exist under `docs/adr/`, each accepted (or, for ADR-006 only, explicitly marked "options recorded, decision deferred to Phase 6") via PR review.

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E02-01 | [docs] STRIDE threat model per data flow | doc | P0 | L |  |
| E02-02 | [docs] ADR-001: native Swift + native Kotlin vs KMP/CMP | adr | P0 | S |  |
| E02-03 | [docs] ADR-002: phone as TLS client, Mac as sole listening server | adr | P0 | S |  |
| E02-04 | [docs] ADR-003: mTLS 1.3 self-signed + SPKI pinning vs. Noise protocol | adr | P0 | M | E03-01, E03-03, E03-04 |
| E02-05 | [docs] ADR-004: QR-only pairing for v1; manual pairing only with a commitment-based SAS | adr | P0 | S |  |
| E02-06 | [docs] ADR-005: two connections (control + media) vs. one multiplexed connection | adr | P0 | M |  |
| E02-07 | [docs] ADR-006: MediaProjection+Accessibility vs. ADB + scrcpy (decision in Phase 6) | adr | P0 | S |  |
| E02-08 | [docs] Threat model part 2: local platform surfaces, storage, logs, CI and supply chain | doc | P0 | M | E02-01 |

### E03 — Phase 0 technical spikes (mTLS on both platforms, Secure Enclave)

Time-boxed spikes to de-risk the two hardest platform-specific unknowns before Phase 1
committed work starts: whether Network.framework's mTLS client-cert + verify-block model
behaves as documented, whether a Secure-Enclave-backed key can serve as the Mac's TLS
identity, and the Android-side equivalent with AndroidKeyStore across the StrongBox/TEE
device matrix. Each spike ends in a written findings doc under `docs/spikes/`, never
production code.

**Exit criteria**

- [ ] Each spike has a findings doc under `docs/spikes/` with a clear go/no-go recommendation.
- [ ] The fallback decision criteria doc (E03-06) exists regardless of whether the fallback spike (E03-05) ran, so Phase 1 has an unambiguous trigger for revisiting ADR-003 if `core/transport`/`TandemTransport` hits the same wall in production code.
- [ ] docs/spikes/channel-binding.md (E03-04) records the channel-binding outcome: exporter on both stacks, or the in-band challenge fallback, which E01-01/E01-02/E01-11/E14-06/E14-07/E70-01 adopt before Phase 1 starts.

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E03-01 | [macos] Spike: NWListener mTLS with client cert, verify block, TLS 1.3 only | spike | P0 | M |  |
| E03-02 | [macos] Spike: Secure Enclave key as sec_identity for the Mac TLS listener | spike | P0 | S |  |
| E03-03 | [android] Spike: SSLSocket client auth with AndroidKeyStore P-256 (StrongBox/TEE) | spike | P0 | M | E00-23 |
| E03-04 | [cross] Spike: end-to-end handshake Android↔Mac hello-world | spike | P0 | M | E03-01, E03-03 |
| E03-05 | [macos] Spike: swift-nio-ssl fallback evaluation (only if Network.framework spike fails) | spike | P2 | M | E03-01 |
| E03-06 | [docs] Fallback decision criteria doc for the TLS stack choice | doc | P0 | S | E03-01 |

## Phase 1 — Identity, pairing, secure transport

### E15 — Security test harness (conformance, pcap-audit, log-audit, mitm-lab, fuzz scaffolding)

Build the security and interoperability test harness that Phase 1's exit criteria depend on,
and that stays in continuous use through every later phase: a conformance runner executing
`protocol/vectors/` (E01) against both the Kotlin and Swift codecs, a pcap-audit tool that
fails a build if anything but TLS 1.3 (or a canary string) appears on the wire, a scripted
MITM lab covering every fail-closed scenario the PRD lists, an `nmap` check proving the
phone opens no listener, short-running fuzz scaffolding for the frame/envelope parsers on
both platforms, and a JVM integration client that runs Android's real `core/*` modules
against the real macOS server. This epic does not implement any protocol or transport
behavior itself; it proves the behavior other epics (E10-E14) implement is correct and fails
closed.

**Exit criteria**

- [ ] Every Phase 1 exit criterion in `docs/PRD.md` `<implementation-roadmap>` is verifiable by running a specific tool or test in this epic — pairing+reconnect → E14-16 (on the E15-15 harness); pcap-audit clean + no canary → E15-05/E15-06/E15-07; every listed mitm-lab scenario fails closed → E15-09/E15-10/E15-11; no phone listeners → E15-12.
- [ ] `tools/conformance/run.sh` is a required CI check on both the android and macos workflows.
- [ ] Fuzz smoke runs complete in CI within a bounded time budget (documented per-issue) with zero crashes on the phase-0 vector corpus.
- [ ] E15-20 passes against the real Mac app: silent TCP closed within 11 s, missing VersionHello closed with PROTOCOL_TIMEOUT within 6 s, over-cap connections closed on accept, a flooding IP refused for 60 s, while a paired client still reaches Ready.
- [ ] E15-23: one `tools/audit/run.sh --subset full` run reports every expected Phase 1 step (device-only steps pending with a manual-gate reference).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E15-01 | [android] Conformance runner: execute protocol/vectors against the Kotlin codec | task | P0 | M | E01-16, E10-03, E10-12, E11-11, E14-03, E14-21 |
| E15-02 | [macos] Conformance runner: execute protocol/vectors against the Swift codec | task | P0 | M | E01-16, E10-08, E10-13, E11-12, E14-22 |
| E15-03 | [ci] Wire conformance runner into CI as a blocking check | task | P0 | S | E15-01, E15-02, E00-11 |
| E15-04 | [tools] pcap-audit: tshark capture harness for the Tandem port | task | P0 | M |  |
| E15-05 | [tools] pcap-audit: "only TLS 1.3 records" assertion | task | P0 | S | E15-04, E15-15 |
| E15-06 | [tools] pcap-audit: canary string scan across full capture | task | P0 | S | E15-04 |
| E15-07 | [tools] Canary procedure script (clipboard, file, notification, mirror injection) | task | P0 | M | E15-04, E15-06, E15-15, E00-23, E14-05, E14-06, E14-08 |
| E15-08 | [tools] mitm-lab: scenario harness scaffolding + scripted-scenario runner | task | P0 | M |  |
| E15-09 | [tools] mitm-lab: pairing-abuse scenarios (replay, expiry, 4th attempt, wrong key) | test | P0 | M | E15-08, E15-15, E14-07, E14-09, E01-18, E01-21, E14-15, E14-02 |
| E15-10 | [tools] mitm-lab: certificate-abuse scenarios (unknown, wrong, swapped cert) | test | P0 | M | E15-08, E15-15, E12-02, E12-05, E14-13 |
| E15-11 | [tools] mitm-lab: downgrade, resumption, 0-RTT and protocol-version scenarios | test | P0 | M | E15-08, E12-01, E12-03, E12-07, E12-10, E15-15 |
| E15-12 | [tools] nmap phone-listener check script | task | P0 | S | E12-08, E00-21, E00-23 |
| E15-13 | [android] Fuzz scaffolding: Jazzer target for the frame/envelope parser + CI smoke run | task | P0 | M | E11-02, E01-19 |
| E15-14 | [macos] Fuzz scaffolding: libFuzzer target for the frame/envelope parser + CI smoke run | task | P0 | M | E11-04, E01-19 |
| E15-15 | [cross] JVM integration-test harness: JVM client against the real Mac server on macOS CI | task | P0 | M | E12-01, E12-02, E15-21, E15-22 |
| E15-17 | [tools] log-audit: canary scan over captured app logs (logcat + macOS unified log) | task | P0 | S | E15-06 |
| E15-18 | [tools] Security audit suite runner: one command, one report | task | P0 | M |  |
| E15-19 | [ci] Security audit CI subset: required check on core/* PRs | task | P0 | S | E15-18, E15-15, E00-11 |
| E15-20 | [tools] mitm-lab: pre-auth DoS and timeout scenarios (slowloris, floods, idle candidates) | test | P0 | M | E15-08, E15-15, E12-18, E12-07, E14-02 |
| E15-21 | [android] JVM harness client: core/* modules on the JVM + jvmIntegrationTest convention | task | P0 | M | E12-04, E12-05, E12-06, E10-15, E00-19 |
| E15-22 | [macos] Harness Mac app driver: launch/restart, CI keychain, trust seeding, pairing hook | task | P0 | M | E13-06, E00-30, E00-24 |
| E15-23 | [tools] Phase 1 security audit gate: every Phase 1 step green in one report | test | P0 | S | E15-18, E15-03, E15-05, E15-06, E15-07, E15-09, E15-10, E15-11, E15-12, E15-13, E15-14, E15-17, E15-20 |

### E10 — Device identity (keys, self-signed certs, SPKI fingerprints)

Each device owns a long-term, non-exportable P-256 key pair and a self-signed X.509 certificate used
purely as a TLS identity; the only thing ever trusted is the SHA-256 hash of the certificate's
SubjectPublicKeyInfo (invariant 3). This epic generates and stores that identity on both platforms,
computes and vector-tests the fingerprint, handles the lifecycle case where the key is missing or
corrupted (a new identity is generated and the device must be re-paired), and provides the small
crypto primitives (constant-time compare, HMAC-SHA256 pairing proof and 6-digit confirmation code)
that transport (E12) and pairing (E14) build on. Only core/crypto (Android) / TandemCrypto (macOS)
may touch key material.

**Exit criteria**

- [ ] Android identity generation succeeds on a StrongBox-capable and a StrongBox-unavailable device profile, never falling back to an exportable key
- [ ] macOS identity key is created in the Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, in the data-protection keychain and the app's own access group only, and is usable as a SecIdentity in Network.framework
- [ ] SPKI fingerprint vectors in protocol/vectors pass on both platforms
- [ ] A corrupted or missing key on either platform yields a fresh identity and an explicit "re-pair required" state, never a crash or silent reuse of stale key material
- [ ] Pairing-proof and confirmation-code vectors (E01-18) pass on both platforms; a non-91-byte SPKI or non-32-byte cb is rejected before any HMAC is computed.

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E10-01 | [android] AndroidKeyStore P-256 key generation (StrongBox, TEE fallback, non-exportable) | task | P0 | M | E00-02, E01-01, E03-03, E10-15, E00-21, E00-23 |
| E10-02 | [android] Self-signed X.509 certificate generation from Keystore key | task | P0 | S | E10-01, E10-15, E00-21 |
| E10-03 | [android] SPKI SHA-256 fingerprint computation (vector-tested) | task | P0 | S | E10-02, E01-17 |
| E10-04 | [android] Identity lifecycle: first-launch bootstrap and corrupted/missing key recovery | task | P0 | M | E10-01, E10-02, E10-03, E10-15, E00-04 |
| E10-05 | [macos] CryptoKit/Security P-256 key generation in Keychain | task | P0 | M | E00-07, E01-01, E03-02, E10-16 |
| E10-06 | [macos] Self-signed certificate via swift-certificates | task | P0 | S | E10-05, E10-16 |
| E10-07 | [macos] SecIdentity construction for Network.framework | task | P0 | S | E10-06, E03-01, E03-02, E10-16 |
| E10-08 | [macos] SPKI SHA-256 fingerprint computation (vector-tested) | task | P0 | S | E10-06, E01-17 |
| E10-09 | [macos] Identity lifecycle: first-launch bootstrap and corrupted/missing key recovery | task | P0 | M | E10-05, E10-06, E10-08, E10-16 |
| E10-10 | [android] Constant-time byte-array compare helper | task | P0 | S | E00-02, E00-04 |
| E10-11 | [macos] Constant-time byte-array compare helper | task | P0 | S | E00-07, E00-08 |
| E10-12 | [android] HMAC-SHA256 pairing-proof helper (vector-tested) | task | P0 | S | E10-03, E01-18 |
| E10-13 | [macos] HMAC-SHA256 pairing-proof helper (vector-tested) | task | P0 | S | E10-08, E01-18 |
| E10-14 | [cross] Module boundary check: only core/crypto and TandemCrypto touch key material | test | P1 | S | E10-01, E10-05, E10-15, E10-16, E00-11 |
| E10-15 | [android] IdentityKeyStore seam + in-memory JCA fake for JVM tests | task | P0 | S | E00-02, E00-04 |
| E10-16 | [macos] KeychainStore seam + in-memory test implementation | task | P0 | M | E00-07, E00-24 |

### E11 — Protocol codec, multiplexer, flow control

Implements the framed transport codec (F-3.2): a u32 big-endian length-prefixed protobuf
Envelope, max 1 MiB, with fail-closed rejection of malformed input; a channel multiplexer
routing CONTROL/NOTIFY/CLIPBOARD/FILES/SMS/CONTACTS/CALLS/INPUT/STATUS frames with seq/ack;
and credit-based per-channel flow control so a large FILES transfer cannot starve NOTIFY.
Both platforms implement independently against the same protocol/vectors fixtures and
design, with conformance and starvation regression tests on each side.

**Exit criteria**

- [ ] Both codecs pass every protocol/vectors frame vector, valid and invalid
- [ ] Oversize, truncated, and garbage input close the connection with close code `MALFORMED_FRAME` (E01-05) on both platforms
- [ ] Every one of 100 NOTIFY frames is delivered within 50 ms of virtual time while a 50 MiB FILES stream saturates a 10 MiB/s link, on both platforms (E11-09, E11-10).
- [ ] A peer sending past its granted credit is closed with CREDIT_VIOLATION on both platforms (E11-07, E11-08).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E11-01 | [android] Envelope frame encode: u32 BE length plus protobuf | task | P0 | S | E00-02, E00-04, E00-09, E01-03, E01-10, E00-19 |
| E11-02 | [android] Envelope frame decode and fail-closed rejection | task | P0 | M | E11-01, E00-19, E01-05 |
| E11-03 | [macos] Envelope frame encode: u32 BE length plus protobuf | task | P0 | S | E00-07, E00-08, E00-09, E01-03, E01-10, E00-25 |
| E11-04 | [macos] Envelope frame decode and fail-closed rejection | task | P0 | M | E11-03, E00-25, E01-05 |
| E11-05 | [android] Channel multiplexer: routing plus seq/ack | task | P0 | M | E11-02, E01-04, E00-04, E00-19 |
| E11-06 | [macos] Channel multiplexer: routing plus seq/ack | task | P0 | M | E11-04, E01-04, E00-25 |
| E11-07 | [android] Flow control: suspending per-channel send, fair frame writer, credit grants | task | P0 | M | E11-05, E11-13, E00-18, E00-19 |
| E11-13 | [android] Per-channel credit ledger (pure accounting) | task | P0 | S | E01-04, E00-04 |
| E11-08 | [macos] Flow control: suspending per-channel send, fair frame writer, credit grants | task | P0 | M | E11-06, E11-14, E00-24, E00-25 |
| E11-14 | [macos] Per-channel credit ledger (pure accounting) | task | P0 | S | E01-04, E00-08 |
| E11-09 | [android] Starvation regression test: FILES transfer must not delay NOTIFY | test | P0 | M | E11-07, E00-18, E00-19 |
| E11-10 | [macos] Starvation regression test: FILES transfer must not delay NOTIFY | test | P0 | M | E11-08, E00-24, E00-25 |
| E11-11 | [android] Conformance: codec against protocol/vectors frame fixtures | test | P0 | S | E11-02, E01-19 |
| E11-12 | [macos] Conformance: codec against protocol/vectors frame fixtures | test | P0 | S | E11-04, E01-19 |

### E12 — Secure transport (mTLS 1.3 client/server, pinning)

Establishes the mutually authenticated TLS 1.3 transport (F-3.1): a macOS NWListener as the sole
listening endpoint on one port, an Android SSLSocket client that always dials, both pinned to the
trust store (E13) with an open-pairing-window exception (E14), a CONTROL-channel Hello for
version/capability negotiation, a connection state machine, fail-closed error surfacing (invariant
5), and a session abstraction over the multiplexer (E11) designed so a future USB transport (F-10.3)
can implement the same interface. It also enforces the cycle-4 TLS profile (ALPN tandem/1, no SNI,
no PSK/0-RTT/post-handshake auth, leaf-only P-256 check, CertificateVerify always enforced), exposes
the RFC 9266 channel binding on TandemSession, and applies pre-auth admission control on the Mac
listener (E12-18).

**Exit criteria**

- [ ] The macOS listener rejects TLS 1.2 (openssl s_client -tls1_2 fails) and rejects an unknown client certificate outside an open pairing window
- [ ] The Android SSLSocket client completes a full handshake against the Mac listener using its Keystore identity
- [ ] The JVM-test-client-to-Mac-server integration test passes in CI
- [ ] A version-mismatched Hello fails closed with a visible error on both sides
- [ ] A client without ALPN tandem/1, a leaf that is not a 91-byte P-256 SPKI, or a pinned certificate without its private key fails the handshake with 0 application bytes; the Android client's second ClientHello carries no pre_shared_key or early_data (E12-01, E12-02, E12-04, E12-05).
- [ ] Client and server channel-binding values are equal 32-byte exporter outputs (E12-01, E12-04), or the E03-04 fallback challenge if the spike chose it.
- [ ] With 8 pre-auth connections a 9th (or a 3rd from one IP) is closed before TLS, an idle TCP connection is closed within 11 s, and a throttled IP never affects a trusted peer from another IP (E12-18).
- [ ] No peer VersionHello within 5 s closes with PROTOCOL_TIMEOUT on both sides (E12-07, E12-15).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E12-01 | [macos] NWListener: TLS 1.3-only mTLS options, single port | task | P0 | M | E10-07, E03-01, E00-07, E01-01 |
| E12-02 | [macos] Verify block: trust store check or open pairing window | task | P0 | M | E12-01, E13-06, E10-08 |
| E12-03 | [macos] Disable session resumption and 0-RTT | task | P0 | S | E12-01 |
| E12-04 | [android] SSLSocket (Conscrypt) TLS 1.3-only client | task | P0 | M | E10-02, E12-06, E00-02, E03-03, E00-19, E10-15, E00-05 |
| E12-05 | [android] Custom X509TrustManager: pin check against trust store or pairing window | task | P0 | M | E12-04, E13-02, E10-03, E10-10 |
| E12-06 | [android] Custom X509KeyManager backed by Keystore identity | task | P0 | S | E10-02, E10-15, E00-21 |
| E12-07 | [macos] CONTROL channel VersionHello: version/capability handshake | task | P0 | M | E12-01, E11-06, E01-06, E00-25, E01-22, E00-24 |
| E12-15 | [android] CONTROL channel VersionHello: version/capability handshake | task | P0 | M | E12-04, E11-05, E01-06, E00-19, E00-04, E01-22, E00-18 |
| E12-08 | [android] Connection state machine | task | P0 | M | E12-04, E12-05, E12-15, E00-18, E00-04, E01-22 |
| E12-09 | [macos] Connection state machine | task | P0 | M | E12-01, E12-02, E12-07, E00-24, E01-22 |
| E12-10 | [macos] Fail-closed error reporting surfaced to the menu | task | P0 | S | E12-09, E12-07, E00-26 |
| E12-16 | [android] Fail-closed error reporting surfaced to the connection-status UI | task | P0 | S | E12-08, E12-15, E00-20 |
| E12-11 | [android] Transport session abstraction exposing channels | task | P0 | M | E12-08, E11-07, E00-19, E00-04 |
| E12-12 | [macos] Transport session abstraction exposing channels | task | P0 | M | E12-09, E11-08, E00-25 |
| E12-13 | [cross] Integration test: JVM client against macOS NWListener server | test | P0 | M | E15-15, E12-02, E12-05, E12-06, E12-07, E12-15 |
| E12-14 | [macos] Record lastSeen and negotiated capabilities in the trust store on Ready | task | P0 | S | E12-07, E12-09, E13-06, E00-24 |
| E12-17 | [android] Record lastSeen and negotiated capabilities in the trust store on Ready | task | P0 | S | E12-15, E12-08, E13-02, E00-18 |
| E12-18 | [macos] Listener admission control: pre-auth connection caps, deadlines, per-IP throttle | task | P0 | M | E12-01, E12-02, E12-09, E01-22, E00-24, E00-25, E03-01 |

### E13 — Trust store and settings storage

Persists the trust store (F-1.2): the peer table keyed strictly by SPKI fingerprint
(invariant 3) that E12's TLS verify logic and E14's pairing flow read and write, plus a
small settings store for user preferences. Both platforms choose a concrete persistence
technology, define migrations, and guarantee that unpair deletes locally and immediately
regardless of connectivity.

**Exit criteria**

- [ ] CRUD operations on both platforms are keyed only by spkiSha256; no API accepts an IP address, hostname, or bare deviceId as a trust key
- [ ] Unpair removes the record and a subsequent read in the same process returns nothing, with no network round-trip required
- [ ] A schema migration test proves a v1-to-v2 change (simulated) does not lose existing peer records
- [ ] macOS trust items are written with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly to the data-protection keychain in the app's own access group, and a locked keychain makes get throw KeychainError.locked (E13-06).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E13-01 | [android] spike: DataStore vs Room for trust store persistence | spike | P0 | S | E00-02 |
| E13-02 | [android] Trust store: peer record schema and CRUD keyed by fingerprint | task | P0 | M | E13-01, E10-03, E00-04 |
| E13-03 | [android] Trust store migrations scaffold | task | P0 | S | E13-02 |
| E13-04 | [android] Settings store for user preferences | task | P1 | S | E00-02, E00-04 |
| E13-05 | [android] Unpair: immediate local trust deletion | task | P0 | S | E13-02 |
| E13-06 | [macos] Trust store: peer record schema and CRUD keyed by fingerprint | task | P0 | M | E10-08, E00-07, E10-16 |
| E13-07 | [macos] Trust store migrations scaffold | task | P0 | S | E13-06 |
| E13-08 | [macos] Settings store for user preferences | task | P1 | S | E00-07, E00-08 |
| E13-09 | [macos] Unpair: immediate local trust deletion | task | P0 | S | E13-06 |
| E13-10 | [android] Trust-store invariant test: fingerprint-only keying | test | P0 | S | E13-02 |
| E13-11 | [macos] Trust-store invariant test: fingerprint-only keying | test | P0 | S | E13-06, E00-11 |

### E14 — QR pairing, unpair, revoke

Implements F-2.1 QR pairing end to end and F-2.3 unpair/revoke: Mac-side QR generation and
pairing-window state machine (one in-flight candidate, 10 s PairRequest deadline), Android-side
scanner (decoder chosen by spike E14-23) and pairing state machine, constant-time proof
verification bound to the handshake certificate and the session channel binding, a 6-digit
confirmation code with mutual confirmation (Mac defaults to Don't Pair; phone commits only after
"Codes match", AC-20), wire PairRejected collapsed to REJECTED_BY_OWNER / PAIRING_UNAVAILABLE,
vector-tested DisplayStringSanitizer on both platforms, and unpair/revoke with per-peer data purge
hooks, culminating in the Phase 1 exit criterion: pair via QR, then reconnect after restarting
both apps.

**Exit criteria**

- [ ] A phone pairs with a Mac via QR and reconnects after restarting both apps
- [ ] Every pairing failure path (bad proof, malformed message, window expiry, candidate idle > 10 s) fails closed, burns exactly one attempt where applicable and sends only PairRejected(PAIRING_UNAVAILABLE) (owner deny: REJECTED_BY_OWNER); a second concurrent candidate is rejected without burning an attempt.
- [ ] Revoke removes trust on both sides when the peer is reachable; local unpair is immediate regardless of reachability
- [ ] Every UC-03 alternate flow (declined, expired/used QR, Mac unreachable) shows a distinct phone message (E14-17)
- [ ] The phone commits the Mac pin only after PairAccepted and "Codes match"; Cancel or 120 s sends Revoke and commits nothing; the Mac dialog defaults to Don't Pair and both sides show the same code (E14-05, E14-08, E14-16).
- [ ] Both DisplayStringSanitizers pass every E01-24 vector (E14-21, E14-22).
- [ ] E14-23 selects a decoder with 0 observed network connections and p95 decode <= 3 s.

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E14-01 | [macos] QR payload generation: secret and payload encode | task | P0 | M | E10-08, E01-02, E01-21, E00-08 |
| E14-02 | [macos] Pairing window state machine | task | P0 | M | E14-01, E00-24, E01-22 |
| E14-03 | [android] QR payload parsing and validation | task | P0 | S | E01-02, E01-21, E00-04, E14-21 |
| E14-04 | [android] Pin Mac fingerprint from QR before TLS connect | task | P0 | S | E14-03, E12-05 |
| E14-05 | [android] Pairing state machine: connect, PairRequest, await result | task | P0 | M | E14-04, E12-08, E12-11, E13-02, E00-18, E00-04, E10-12 |
| E14-06 | [android] Compute pairing proof and attach to PairRequest | task | P0 | S | E10-12, E10-03, E10-15, E14-05, E12-11, E03-04 |
| E14-07 | [macos] Constant-time proof verification bound to handshake cert | task | P0 | M | E14-02, E10-11, E10-13, E12-02, E03-04 |
| E14-08 | [macos] Pairing confirmation dialog and PairAccepted/reject | task | P0 | M | E14-07, E13-06, E12-12, E14-22, E10-13 |
| E14-09 | [macos] Failure handling: any pairing failure closes connection and burns attempt | task | P0 | S | E14-07, E14-02, E00-24, E12-12 |
| E14-10 | [android] CameraX QR scanner UI (decoder chosen by E14-23) | task | P0 | M | E14-03, E00-20, E00-21, E00-23, E14-23, E00-31 |
| E14-11 | [macos] Pairing UI: QR display, countdown, regenerate | task | P0 | M | E14-01, E14-02, E00-24, E00-26, E00-32 |
| E14-12 | [android] Unpair action: local deletion and Revoke if connected | task | P0 | S | E13-05, E12-11, E00-18 |
| E14-13 | [macos] Unpair action: local deletion and Revoke if connected | task | P0 | S | E13-09, E12-12, E00-24 |
| E14-14 | [macos] Paired-devices list UI: last-seen and revoke button | task | P0 | M | E13-06, E14-13, E12-14, E00-24, E00-26 |
| E14-15 | [macos] Revoke message handling: receiver drops session and trust | task | P0 | S | E14-13, E12-02, E12-12 |
| E14-19 | [android] Revoke message handling: receiver drops session and trust | task | P0 | S | E14-12, E12-11, E12-08 |
| E14-20 | [cross] Integration: revoke over the JVM harness (connected and offline) | test | P0 | S | E15-15, E14-12, E14-13, E14-15, E14-19, E12-16 |
| E14-16 | [cross] End-to-end: QR pair then reconnect after restarting both apps | test | P0 | L | E15-15, E14-05, E14-06, E14-08 |
| E14-17 | [android] Pairing failure messages: expired/used QR, declined, Mac unreachable | story | P0 | S | E14-05, E12-16, E00-20, E00-31 |
| E14-18 | [android] Keystore client-auth device matrix test (StrongBox, TEE-only, API 29, OEM) | test | P0 | M | E10-01, E10-15, E12-04, E12-06, E14-10, E00-21, E00-23, E14-05, E14-06, E14-08, E14-11 |
| E14-21 | [android] DisplayStringSanitizer (vector-tested) | task | P0 | S | E01-24, E00-04 |
| E14-22 | [macos] DisplayStringSanitizer (vector-tested) | task | P0 | S | E01-24, E00-08 |
| E14-23 | [android] Spike: QR decoder choice (ML Kit bundled telemetry vs. zxing-cpp) | spike | P0 | S | E00-23 |

## Phase 2 — Lifecycle and reliability

### E20 — Android connection lifecycle (foreground service, heartbeat, reconnect)

Keep the phone's control connection alive across app kills, OEM battery policies, Doze,
reboots, and network changes, and keep the Mac side resilient to sleep/wake and interface
changes. Done means the phone reconnects to a woken or roaming Mac in under 5 s p95
without user action, survives an overnight Doze cycle, and always shows accurate
connection state.

**Exit criteria**

- [ ] Phone reconnects to Mac within 5 s p95 over >= 20 Wi-Fi switch trials (E20-12 manual gate reconnectWifiSwitch_twentyTrials_p95Under5s)
- [ ] Phone reconnects within 5 s p95 over >= 20 Mac sleep/wake trials (E20-12 manual gate reconnectMacWake_twentyTrials_p95Under5s)
- [ ] Over >= 8 h of Doze with the foreground service running, battery unrestricted and zero user interaction, every Mac-declared-dead episode is followed by a reconnect within 5 s of the next Doze maintenance window or screen-on (E20-12 manual gate overnightDoze8h_fgsUnrestrictedBattery_reconnectWithin5sOfWake)
- [ ] Mac sends Heartbeat after 15 s without sending and marks the connection Dead after 45 s without receiving (E20-05); the phone answers every Heartbeat within 1 s, including under adb-forced idle (E20-15)
- [ ] Foreground service is restarted by the system after process death (E20-02) and starts after reboot (E20-08), without relying on CompanionDeviceManager

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E20-01 | [protocol] Heartbeat conformance vectors | task | P0 | S | E01-12, E01-16, E15-01, E15-02 |
| E20-02 | [android] Foreground service (connectedDevice type) | task | P0 | M | E12-08, E12-11, E13-02, E00-20, E00-21, E00-23 |
| E20-03 | [android] Spike: CompanionDeviceManager presence feasibility for a Wi-Fi-only Mac peer | spike | P0 | M |  |
| E20-04 | [android] Unrestricted battery onboarding and OEM guidance | story | P0 | M | E20-02, E00-20, E00-23 |
| E20-05 | [macos] Heartbeat sender and dead-peer detection (Mac drives liveness) | task | P0 | M | E20-01, E12-09, E00-24, E00-25 |
| E20-06 | [android] Reconnect address strategy and exponential backoff | task | P0 | M | E21-05, E12-08, E00-18, E15-15 |
| E20-07 | [android] Reconnect on ConnectivityManager network callback | task | P0 | S | E20-06, E00-18, E00-20 |
| E20-08 | [android] Service restart on BOOT_COMPLETED and MY_PACKAGE_REPLACED | task | P0 | S | E20-02, E00-20, E00-23, E00-28 |
| E20-09 | [android] Connection state UI on phone | story | P0 | S | E20-06, E12-16, E00-18, E00-20 |
| E20-10 | [macos] Sleep/wake handling via NSWorkspace | task | P0 | M | E12-01, E12-09, E00-08, E00-24 |
| E20-11 | [macos] Listener restart on network path change | task | P0 | M | E12-01, E00-08 |
| E20-12 | [tools] Reconnect latency measurement harness and overnight Doze gate | test | P0 | M | E20-05, E20-15, E20-06, E20-07, E20-10, E20-11, E15-15, E00-23 |
| E20-13 | [docs] ADR: Mac-initiated reconnect hint (PRD Appendix C.3) | adr | P1 | S | E20-12, E02-03, E20-03 |
| E20-14 | [android] Onboarding flow: per-permission explanations with skip paths | story | P0 | M | E20-04, E14-10, E10-04, E00-20 |
| E20-15 | [android] Heartbeat responder, Doze-aware timer, sleep-inclusive dead-peer detection | task | P0 | L | E20-01, E12-08, E12-11, E00-18, E00-19, E00-20, E00-23 |
| E20-16 | [android] CompanionDeviceManager association (+ presence restart if E20-03 = go) | task | P1 | M | E20-03, E20-02, E14-05, E14-12, E00-20, E00-23 |
| E20-17 | [android] App shell: floating toolbar navigation and Home status ring | story | P0 | M | E00-31, E20-09, E12-16 |
| E20-18 | [android] Activity tab: metadata-only feed with 7-day retention *(lands Phase 3)* | story | P1 | M | E20-17, E13-04 |
| E20-19 | [android] Settings tab: paired Mac, battery, key, unpair | story | P1 | S | E20-17, E14-12, E20-04 |
| E20-20 | [tools] mitm-lab: authenticated heartbeat/CONTROL flood | test | P1 | S | E20-15, E20-05, E15-08 |

### E21 — Bonjour discovery with rotating ID

Let phones find a Mac on the local network without leaking a stable identifier to
observers. The Mac advertises a rotating pseudonymous id derived from its long-term key;
paired phones recognize it, strangers cannot correlate it across days. Discovery only
supplies candidate addresses; it never substitutes for the mTLS fingerprint check.

**Exit criteria**

- [ ] Both codecs match every E01-20 rotating-id vector, and the advertised TXT id and instance name change at the UTC day boundary (E21-02, E21-05)
- [ ] Android recognizes a paired Mac's rotating id for dayIndex-1..+1 only, and a spoofed advertisement with the right id but wrong key fails the pin check with zero application bytes (E21-06)
- [ ] macOS shows the Local Network permission prompt and advertises once granted; denial shows the in-app explanation (E21-03)

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E21-02 | [macos] Advertise _tandem._tcp with rotating TXT id | task | P0 | M | E01-08, E01-20, E12-01, E00-24, E15-02, E00-23, E20-10 |
| E21-03 | [macos] Local Network privacy entries and permission handling | task | P0 | S | E21-02, E00-26, E00-23 |
| E21-04 | [android] NsdManager browse and resolve | task | P0 | M | E01-08, E00-18, E00-21, E00-23 |
| E21-05 | [android] Recognize paired Macs from rotating id | task | P0 | M | E21-04, E13-02, E01-20, E00-18, E15-01 |
| E21-06 | [cross] Discovery is a hint, never a trust decision | test | P0 | S | E21-05, E20-06, E15-08, E15-10, E15-15 |
| E21-07 | [cross] Rotating id recognition across day boundary and skew | test | P1 | S | E01-20, E21-02, E21-05, E15-03, E15-15 |

### E22 — macOS menu bar agent and connection UI

The always-available Mac surface: a menu bar item showing connection state and battery,
quick actions for the core features, launch at login, and the paired-devices management
UI. Also the single place errors defined by invariant 5 (pin mismatch, unknown peer,
version mismatch) are surfaced to the user.

**Exit criteria**

- [ ] Menu bar view model reflects the live connection state within 1 s of a transition (E22-01)
- [ ] Launch at login brings the menu bar icon back within 60 s of login after a full reboot (E22-03 manual gate)
- [ ] A pin-mismatch or version-mismatch error is shown as a persistent banner until acknowledged, not only logged (E22-07)
- [ ] codesign on the Release build shows exactly app-sandbox, network.server and network.client, the hardened-runtime flag, and no cs.* or get-task-allow entitlement (E22-04).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E22-01 | [macos] MenuBarExtra scaffold with connection state and battery | task | P0 | M | E12-09, E12-12, E00-24, E00-26 |
| E22-02 | [macos] Quick actions menu | task | P0 | S | E22-01, E00-26 |
| E22-03 | [macos] Launch at login via SMAppService | task | P0 | S | E22-01, E00-08, E00-23 |
| E22-04 | [macos] App Sandbox entitlements for network client/server | task | P0 | S | E12-01, E00-23 |
| E22-05 | [macos] Settings window shell | task | P1 | S | E22-01, E14-14, E00-26 |
| E22-07 | [macos] Visible error surfacing for fail-closed events | story | P0 | M | E22-01, E12-10, E12-12, E00-24, E00-26 |
| E22-08 | [macos] Bind menu bar state to sleep/wake and network restarts | task | P1 | S | E22-01, E20-10, E20-11, E00-24 |
| E22-09 | [macos] Main window shell: glass sidebar, sections, offline/empty states | story | P1 | M | E00-32, E22-01, E22-07 |

### E23 — Device status and find my phone

The phone reports battery, charging, network type, and signal on the STATUS channel so
the Mac can show it at a glance, and the Mac can ring the phone at max volume (overriding
DND) to help find it, with dismiss/stop from either side.

**Exit criteria**

- [ ] A battery/network change outside the 60 s throttle window is shown on the Mac within 2 s (E23-08)
- [ ] Ring is audible at max volume on a physical phone in silent mode with DND on, and stops within 1 s of Stop from the Mac or dismissal on the phone (E23-05, E23-08 manual gates)

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E23-01 | [protocol] status.proto extension: RingStop, STATUS SPEC section, vectors | task | P0 | S | E01-13, E01-16, E15-01, E15-02 |
| E23-02 | [android] Battery/network/signal observers | task | P0 | M | E23-01, E20-02, E20-07, E00-04, E00-20 |
| E23-03 | [android] Publish-on-change with 60 s throttle | task | P0 | S | E23-02, E12-11, E00-18 |
| E23-04 | [macos] STATUS channel display | story | P0 | S | E23-01, E22-01, E12-12, E00-26 |
| E23-05 | [android] Ring handler: max volume overriding DND | story | P0 | M | E23-01, E20-02, E00-20, E00-21, E00-23 |
| E23-06 | [android] Ring dismiss/stop from phone and Mac | task | P0 | S | E23-05, E12-11, E00-21 |
| E23-07 | [macos] Find my phone quick action wired to Ring/RingStop | story | P0 | S | E23-01, E22-02, E12-12, E00-26 |
| E23-08 | [cross] Status throttle and ring round-trip tests | test | P0 | S | E23-03, E23-04, E23-06, E23-07, E15-15, E00-23 |

## Phase 3 — Notifications and clipboard

### E30 — Notification mirroring, actions, replies, dismiss sync

Mirror Android notifications to the Mac with app identity, icons, and conversation
sender names; let the user act on or reply to them from the Mac; keep dismissal and
lock-screen privacy in sync both ways. Exit test: reply to a WhatsApp and a Signal
notification from the Mac.

**Exit criteria**

- [ ] Replying to a WhatsApp notification from the Mac delivers the reply in WhatsApp
- [ ] Replying to a Signal notification from the Mac delivers the reply in Signal
- [ ] Dismissing a notification on either side removes it on the other within 1 s
- [ ] No notification text or secrets appear in release-build logs (invariant 7)
- [ ] Android-post to Mac-presentation p95 < 500 ms over 200 notifications on the same Wi-Fi (E30-14).
- [ ] Phase 3 start: the companion test app (E00-22, lands this phase) builds in CI and is installed on the managed devices before instrumented tests run.

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E30-01 | [protocol] notify.proto: posted/action/dismiss/icon messages | task | P0 | M | E01-05, E01-10, E01-14, E01-16, E15-01, E15-02, E01-22, E01-23 |
| E30-02 | [android] NotificationListenerService capture and mapping | task | P0 | M | E30-01, E00-20, E00-21, E00-22, E00-28 |
| E30-03 | [android] Default notification filter | task | P0 | S | E30-02, E00-20 |
| E30-04 | [android] Per-app allow/deny settings | story | P0 | M | E30-03, E00-20, E12-11 |
| E30-05 | [android] Icon extraction, send once per version | task | P1 | M | E30-02, E00-20 |
| E30-06 | [macos] Icon cache keyed by package and version | task | P1 | S | E30-01, E30-07, E22-01, E00-08, E14-13 |
| E30-07 | [macos] UNUserNotificationCenter presentation via NotificationPresenter seam | story | P0 | M | E30-01, E22-01, E00-08, E12-12, E00-23, E14-22, E14-13 |
| E30-08 | [macos] Forward action/reply as NotificationAction | task | P0 | S | E30-07, E30-17, E12-12 |
| E30-09 | [android] Fire PendingIntent from received NotificationAction | story | P0 | M | E30-01, E30-02, E20-02, E12-11, E00-20, E00-21, E00-22 |
| E30-10 | [android] Dismiss sync: forward phone dismissals, apply Mac dismissals | story | P0 | S | E30-02, E12-11, E00-20, E00-21, E00-22 |
| E30-11 | [android] VISIBILITY_SECRET content handling (phone-side opt-in) | story | P0 | M | E30-02, E30-04, E00-20, E00-21, E00-22 |
| E30-12 | [android] Rate limiting and coalescing of rapid updates | task | P1 | S | E30-02, E00-18, E00-21, E00-22 |
| E30-13 | [cross] Phase 3 notification exit test | test | P0 | M | E30-08, E30-09, E30-10, E30-18, E30-11, E15-17, E15-07, E00-22, E00-23 |
| E30-14 | [tools] Notification latency harness: Android to Mac p95 < 500 ms | test | P0 | M | E30-02, E30-07, E20-02, E00-22, E00-23, E15-15 |
| E30-15 | [macos] Hide notification content while the Mac is locked | story | P1 | S | E30-07, E30-17, E13-08, E00-08, E00-23 |
| E30-16 | [android] Disconnected notification buffer: bounded, drop-oldest, memory only | task | P0 | S | E30-01, E30-02, E00-18, E12-11 |
| E30-17 | [macos] Notification categories: phone actions, text-input reply, custom dismiss | task | P0 | M | E30-01, E30-07, E00-08, E00-23 |
| E30-18 | [macos] Dismiss sync: remove on phone dismissal, forward Mac dismissals | story | P0 | S | E30-07, E30-17, E12-12 |

### E31 — Clipboard sync

Sync clipboard text Mac to phone by polling NSPasteboard, and phone to Mac through the
entry points Android 10+ allows in the background. Skip anything the source app marked
concealed or transient, prevent echo loops, and cap size at 1 MiB.

**Exit criteria**

- [ ] No clipboard echo loops occur across a round trip in either direction
- [ ] A concealed pasteboard item (password manager) never leaves the Mac
- [ ] Clipboard text over 1 MiB is rejected, not silently truncated
- [ ] A clip sent with sensitive=true is written on the Mac with ConcealedType and TransientType markers (E31-13).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E31-01 | [protocol] clipboard.proto: ClipboardText message | task | P0 | S | E01-05, E01-10, E01-14, E01-16, E15-01, E15-02 |
| E31-02 | [macos] NSPasteboard changeCount polling via PasteboardSource seam | task | P0 | S | E31-01, E00-08, E00-24 |
| E31-03 | [macos] Concealed/transient pasteboard type skip | task | P0 | S | E31-02 |
| E31-04 | [macos] Send ClipboardText on qualifying change | task | P0 | S | E31-03, E12-12 |
| E31-05 | [android] Receive and write clipboard with sensitive flag | task | P0 | S | E31-01, E20-02, E12-11, E00-20, E00-23 |
| E31-06 | [android] Share target and PROCESS_TEXT entry points | story | P0 | M | E31-01, E12-11, E00-20, E00-28 |
| E31-07 | [android] Foreground capture and in-app Send clipboard button | task | P0 | S | E31-01, E31-06, E00-20 |
| E31-08 | [android] Origin tag and content-hash loop prevention | story | P0 | S | E31-05, E31-06, E31-07 |
| E31-09 | [docs] ADR: accessibility-based clipboard auto-capture | adr | P1 | S |  |
| E31-10 | [cross] Clipboard exit test: no echo loop, concealed never leaves Mac | test | P0 | M | E31-08, E31-14, E31-03, E31-05, E15-17, E15-07, E15-06, E00-25, E00-23 |
| E31-11 | [macos] Push Clipboard quick action | story | P1 | S | E22-02, E31-03, E31-04, E12-12 |
| E31-12 | [android] Quick Settings tile entry point | story | P0 | S | E31-06, E31-07, E00-20, E00-21, E00-28 |
| E31-13 | [macos] Receive ClipboardText and write NSPasteboard | task | P0 | S | E31-01, E31-02, E12-12 |
| E31-14 | [macos] Origin tag and content-hash loop prevention | story | P0 | S | E31-04, E31-13, E00-24, E00-25, E12-12 |

## Phase 4 — Files and photos

### E40 — File transfer (both directions, resumable)

Move files in either direction with an explicit offer/accept handshake, chunked and
flow-controlled transfer, whole-file integrity verification, and resume after a dropped
connection. Both platforms get native entry points (drag-drop, Share extension, Finder
Services on the Mac; share target and SAF picker on Android) and a progress UI.

**Exit criteria**

- [ ] A 4 GB file transfers successfully in both directions with a forced disconnect midway, and the SHA-256 matches after resume
- [ ] With a saturating FILES transfer, NOTIFY p95 < 100 ms and max < 500 ms over >= 200 frames on the E15-15 harness, and p95 < 500 ms on real Wi-Fi during a 4 GB transfer (E40-15).
- [ ] During the 4 GB manual run peak memory stays <= 64 MiB above idle and no .part file remains (E40-14).
- [ ] Over-cap offers are rejected BUSY / TOO_LARGE without a prompt on both platforms (E40-07, E40-18).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E40-01 | [protocol] files.proto: offer/accept/chunk/complete/cancel/resume | task | P0 | M | E01-05, E01-10, E01-14, E01-16, E15-01, E15-02, E15-03, E01-22 |
| E40-02 | [protocol] Filename sanitization rule and shared vectors | task | P0 | S | E40-01, E15-01, E15-02, E15-03 |
| E40-03 | [android] Sender: chunked read, hashing, flow control | task | P0 | L | E40-01, E40-02, E11-07, E12-11, E00-18, E00-19 |
| E40-04 | [macos] Sender: chunked read, hashing, flow control | task | P0 | L | E40-01, E40-02, E11-08, E12-12, E00-24, E00-25 |
| E40-05 | [android] Receiver: temp file, verify, atomic move to MediaStore | task | P0 | L | E40-01, E40-16, E12-11, E00-18, E00-20, E00-21, E14-12 |
| E40-06 | [macos] Receiver: temp file, verify, atomic move to Downloads/Tandem | task | P0 | L | E40-01, E40-17, E12-12, E00-24 |
| E40-07 | [android] Accept, auto-accept, and disk-space pre-check | story | P0 | M | E40-01, E12-11, E00-18, E00-20, E14-21 |
| E40-08 | [android] Resume by offset after disconnect | story | P0 | L | E40-03, E40-05, E12-11, E00-18, E00-19 |
| E40-09 | [android] Cancel transfer cleanup | task | P1 | S | E40-03, E40-05, E00-19 |
| E40-10 | [macos] Drag-drop and Send File quick action entry points | story | P1 | M | E40-04, E22-01, E22-02, E00-26 |
| E40-11 | [android] Share target and SAF picker entry points | story | P1 | M | E40-03, E00-20, E00-28 |
| E40-12 | [android] Transfer progress UI | story | P1 | M | E40-03, E40-05, E40-09, E00-18, E00-20 |
| E40-13 | [android] Received-file notification | task | P1 | S | E40-05, E00-20 |
| E40-14 | [tools] 4 GB transfer with forced disconnect | test | P0 | L | E40-08, E40-19, E15-15, E00-23 |
| E40-15 | [tools] Flow-control no-starvation test | test | P0 | M | E40-03, E40-04, E11-09, E11-10, E30-14, E15-15, E00-23 |
| E40-16 | [android] FilenameSanitizer | task | P0 | S | E40-02, E15-01 |
| E40-17 | [macos] FilenameSanitizer | task | P0 | S | E40-02, E15-02 |
| E40-18 | [macos] Accept, auto-accept, and disk-space pre-check | story | P0 | M | E40-01, E12-12, E00-24, E14-22 |
| E40-19 | [macos] Resume by offset after disconnect | story | P0 | L | E40-04, E40-06, E12-12, E00-24, E00-25 |
| E40-20 | [macos] Cancel transfer cleanup | task | P1 | S | E40-04, E40-06, E00-25 |
| E40-21 | [macos] Finder Services "Send to phone" entry point | story | P1 | S | E40-04 |
| E40-22 | [macos] Share extension target "Send to phone" | story | P1 | M | E40-04 |
| E40-23 | [macos] Transfer progress UI | story | P1 | M | E40-04, E40-06, E40-20, E00-24, E00-26 |
| E40-24 | [macos] Received-file notification | task | P1 | S | E40-06 |

### E41 — Photo browser

Let the Mac browse the phone's photo library as a paged grid with cached thumbnails and
download originals through the existing file-transfer machinery, respecting Android's
scoped and partial media permissions.

**Exit criteria**

- [ ] A 10 000-item library pages in exactly 100 PhotoPage requests with <= 300 decoded thumbnails in memory, disk cache within its cap and < 150 MiB peak memory growth (E41-09); Android reads <= limit + 1 rows per page (E41-11).
- [ ] Selecting partial access on Android 14+ re-triggers a photo re-selection prompt when more photos are requested
- [ ] An original download completes and matches the source file's hash via the E40 pipeline

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E41-01 | [protocol] photos.proto: PhotoPage and Thumb messages | task | P0 | S | E01-05, E01-10, E01-14, E01-16, E01-04, E15-01, E15-02, E15-03, E01-22 |
| E41-02 | [android] Media permission handling (full and partial access) | story | P0 | M | E20-02, E41-01, E00-20, E00-21 |
| E41-03 | [android] MediaStore cursor-paged query | task | P0 | M | E41-01, E41-02, E00-20, E00-21 |
| E41-04 | [android] Thumbnail generation via ThumbRequest | task | P0 | M | E41-01, E41-02, E00-21 |
| E41-05 | [macos] Photo grid UI with paging | story | P0 | M | E41-01, E22-01, E12-12, E00-26 |
| E41-06 | [macos] LRU disk thumbnail cache with size cap | task | P0 | M | E41-05, E14-13 |
| E41-07 | [android] Serve original download via file transfer | story | P0 | S | E41-01, E41-02, E40-03, E12-11 |
| E41-08 | [android] Partial-access and paging correctness test | test | P1 | S | E41-02, E41-03, E00-21, E00-23 |
| E41-09 | [macos] 10k-library scroll test: visible-cell thumbnails, bounded cache and memory | test | P0 | M | E41-05, E41-06, E00-26 |
| E41-10 | [macos] Download original from the photo grid | story | P0 | S | E41-05, E40-06, E40-18, E15-15 |
| E41-11 | [android] 10k-library paging and thumbnail load test | test | P0 | S | E41-03, E41-04 |

## Phase 5 — Messaging, contacts, calls

### E50 — SMS read, sync, send

Read-only sync of SMS threads and messages from the Android Telephony provider to the Mac
(initial paged backfill + incremental _id-watermark sync via ContentObserver), and sending
SMS from the Mac through SmsManager with sent/delivered status reported back, including
multi-SIM subscription choice. Sync cursors are Mac-authoritative: the Mac persists
highWatermarkId/backfillCursorId and sends them on every reconnect, so the phone keeps no
per-Mac sync state. Includes the Mac conversation UI (thread list, message view, compose),
the Mac GRDB/SQLite SMS store, and documents Android's non-default-SMS-app behaviour
(system writes the Sent row; Tandem cannot update/delete provider rows). MMS and RCS are
explicitly out of scope for v1.

**Exit criteria**

- [ ] Send and receive SMS from the Mac (roadmap Phase 5 exit criterion).
- [ ] A 5k-message fixture completes initial sync in pages of <= 200 messages with no gaps or duplicates across a forced mid-sync disconnect (E50-10).
- [ ] A log audit (tools/log-audit, E15-17) over a canary SMS session finds zero occurrences of the canary body or number in logs (invariant 7).
- [ ] A body over 1600 characters fails TOO_LONG and an 11th send within 60 s fails RATE_LIMITED, without calling SmsManager (E50-04).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E50-01 | [protocol] sms.proto: threads, messages, sync cursors, send, SIM list | task | P0 | M | E01-10, E01-14, E01-16, E15-01, E15-02, E01-22 |
| E50-02 | [android] SMS provider read via SmsSource: paged query + row mapping | task | P0 | M | E50-01, E00-20, E00-21 |
| E50-03 | [android] Incremental SMS sync via _id watermark + ContentObserver | task | P0 | M | E50-13, E00-18, E00-21 |
| E50-04 | [android] SmsManager multipart send with delivery status | story | P0 | L | E50-01, E50-02, E12-11, E00-20, E00-23 |
| E50-05 | [android] Multi-SIM subscription chooser for send + SimList | task | P0 | M | E50-04, E00-23 |
| E50-06 | [docs] Document non-default-SMS-app provider behavior | doc | P0 | S | E50-04 |
| E50-07 | [macos] Conversation thread list UI | story | P0 | M | E50-01, E50-09, E51-04, E22-01, E00-08, E14-22 |
| E50-08 | [macos] Message view + compose | story | P0 | M | E50-07, E50-01, E50-14, E12-12, E00-08 |
| E50-09 | [macos] Local SMS store: GRDB SQLite persistence + at-rest decision | task | P0 | L | E50-01, E14-13, E00-08 |
| E50-10 | [cross] End-to-end SMS sync + send integration test | test | P0 | M | E50-03, E50-04, E50-08, E50-13, E50-14, E15-15, E00-23 |
| E50-11 | [tools] Security test: SMS content never logged | test | P0 | S | E50-13, E50-04, E50-14, E15-15, E15-17 |
| E50-12 | [android] Spike: confirm MMS/RCS scope from the owner's real message mix (Appendix C.4) | spike | P1 | S |  |
| E50-13 | [android] Initial SMS sync session: paged streaming, credits, cursor resume | task | P0 | M | E50-02, E11-07, E12-11, E20-02 |
| E50-14 | [macos] SMS sync client: request on connect, apply batches, reconcile sends | task | P0 | M | E50-01, E50-09, E12-12, E00-08 |

### E51 — Contacts sync

Read-only sync of contact name, phone numbers, emails, and a photo thumbnail from
ContactsContract to a Mac-side cache, kept current via an updated-timestamp watermark and
ContactsContract.DeletedContacts. Phone numbers are normalized to E.164 on both platforms
(Android via Google's libphonenumber, macOS via a Swift port) so SMS senders and call
caller IDs match cached contacts regardless of the number's original formatting. The Mac
cache uses the same GRDB SQLite approach as the SMS store (E50-09). This epic has no UI of
its own; it is a dependency of E50's thread list and E52's caller-ID alert.

**Exit criteria**

- [ ] A 500-contact fixture's initial sync matches on the Mac; a subsequent edit and a delete are both reflected within 2 s, as one updated record plus one tombstone with no full resync (E51-07).
- [ ] Phone-number-normalization vectors produce identical E.164 output on both platforms.
- [ ] A log audit over a full contacts sync session finds zero occurrences of canary contact PII (invariant 7).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E51-01 | [protocol] contacts.proto: contact record, sync, delete | task | P0 | M | E01-10, E01-14, E01-16, E15-01, E15-02 |
| E51-02 | [android] ContactsContract read via ContactsSource + paged sync session | task | P0 | M | E51-01, E20-02, E11-07, E12-11, E00-20, E00-21 |
| E51-03 | [android] Phone number normalization (libphonenumber) | task | P0 | S | E51-02 |
| E51-04 | [macos] Contacts cache (GRDB) + lookup API + sync client | task | P0 | M | E51-01, E50-09, E14-13, E12-12, E00-08 |
| E51-05 | [android] Incremental contacts sync via updated timestamp + deleted contacts | task | P0 | M | E51-02, E00-18, E00-20, E00-21 |
| E51-06 | [protocol] Phone-number-normalization parity vectors | test | P1 | S | E51-03, E51-04, E01-16, E15-01, E15-02 |
| E51-07 | [cross] End-to-end contacts sync integration test | test | P0 | M | E51-02, E51-04, E51-05, E51-09, E15-15, E00-23 |
| E51-08 | [tools] Security test: contact PII never logged | test | P0 | S | E51-02, E51-04, E15-15, E15-17 |
| E51-09 | [android] Contact thumbnail downsampling | task | P0 | S | E51-02, E51-01, E00-20 |

### E52 — Calls control

Incoming-call detection with caller ID resolved via the contacts cache (E51), a Mac alert
shown within 1 s with answer/decline actions, hang up of an active call, and placing
outgoing calls from the Mac. Audio always stays on the phone (PRD non-goal: no Bluetooth
HFP audio bridging). A spike first settles which Android call APIs to use so detection and
control do not require becoming the default dialer or a call-screening app.

**Exit criteria**

- [ ] Incoming call shows on the Mac within 1 s p95 (roadmap Phase 5 exit criterion).
- [ ] Answer, decline, hang up, and place-call all work from the Mac in a device-level test.
- [ ] A log audit over a call-control session finds zero occurrences of canary caller identity (invariant 7).
- [ ] An MMI/USSD string (e.g. **21*123#) returns INVALID_NUMBER and a second PlaceCallRequest within 5 s returns RATE_LIMITED, with no call placed (E52-05).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E52-01 | [protocol] calls.proto: call events, actions, place call | task | P0 | M | E01-10, E01-14, E01-16, E15-01, E15-02, E01-22 |
| E52-02 | [android] Spike: choose call-detection and control APIs | spike | P0 | S |  |
| E52-03 | [android] Incoming call detection via TelephonyCallback | task | P0 | M | E52-01, E52-02, E20-02, E51-03, E12-11, E00-18, E00-21 |
| E52-04 | [android] Answer/decline/hangup via TelecomManager | story | P0 | M | E52-01, E52-03, E12-11, E00-21 |
| E52-05 | [android] Place outgoing call + background-start handling | story | P0 | M | E52-01, E52-02, E52-03, E50-05, E12-11 |
| E52-06 | [macos] Incoming call alert UI | story | P0 | M | E52-01, E51-04, E22-01, E30-07, E12-12, E00-08, E14-22 |
| E52-07 | [macos] Place call UI | story | P0 | S | E52-01, E51-04, E50-08, E12-12, E00-08 |
| E52-08 | [cross] Device-level test: call control latency and correctness | test | P0 | M | E52-03, E52-04, E52-05, E52-06, E52-07, E00-23 |
| E52-09 | [tools] Security test: call metadata never logged | test | P0 | S | E52-03, E52-04, E52-05, E52-06, E15-15, E15-17 |

## Phase 6 — Mirroring and remote input

### E60 — Media connection with ticket binding

A second mTLS connection, dedicated to the high-bandwidth, latency-sensitive mirroring
stream, so a saturated file transfer or SMS backfill on the control connection never
delays a video frame (ADR-005: two connections vs. one multiplexed connection). The media
connection is still full mTLS with the same pinned identities as the control connection; a
single-use, 30 s-expiry mediaTicket issued over the control channel binds it to the
originating control session so an unauthenticated party cannot open or hijack it (AC-08).

**Exit criteria**

- [ ] mitm-lab media-ticket scenarios (missing, reused, expired, other-session, other-client-cert ticket) all fail closed.
- [ ] pcap-audit shows only TLS 1.3 records for both the control and the media connection on the single Tandem port during a mirror session (no second listener).
- [ ] With the control connection saturated by a 500 MB FILES transfer, p95 MediaFrame delivery on the E15-15 harness is within 10 ms of baseline and < 120 ms, and mirroring during a 1 GB transfer keeps p95 < 120 ms on 5 GHz Wi-Fi (E60-07).
- [ ] A media connection that sends no MediaHello within 5 s is closed with PROTOCOL_TIMEOUT (E60-05).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E60-01 | [protocol] media.proto: ticket issuance + MediaHello binding | task | P0 | M | E01-09, E01-12, E01-16, E02-06, E15-01, E15-02 |
| E60-02 | [android] Media ticket request + second mTLS connection dial | task | P0 | M | E60-01, E60-03, E12-08, E12-11, E00-19, E15-15 |
| E60-03 | [macos] Media connection acceptor on the single listener | task | P0 | M | E60-01, E60-08, E12-01, E12-02, E12-12, E00-25, E00-24, E01-22 |
| E60-04 | [macos] Media connection lifecycle tied to control session | task | P0 | M | E60-03, E12-09, E12-12, E00-24 |
| E60-05 | [tools] Security test: media ticket binding scenarios | test | P0 | M | E60-03, E60-04, E15-08 |
| E60-06 | [tools] pcap-audit coverage for the media connection | test | P0 | S | E60-04, E60-09, E15-04, E15-05 |
| E60-07 | [cross] Media connection isolation from control-channel congestion | test | P0 | M | E60-04, E60-09, E11-07, E11-08, E15-15, E00-23 |
| E60-08 | [macos] MediaTicket issuer + validator (30 s expiry, single use, session binding) | task | P0 | M | E60-01, E10-11, E00-24 |
| E60-09 | [android] Media connection lifecycle tied to control session | task | P0 | S | E60-02, E12-08, E12-11, E00-18, E15-15 |

### E61 — Screen mirroring (capture, encode, decode, render)

Android-side capture via MediaProjection and VirtualDisplay, H.264 (HEVC when both sides
support it) low-latency CBR encoding via MediaCodec, and macOS-side decoding via
VTDecompressionSession into a resizable AVSampleBufferDisplayLayer window. Includes
rotation/resolution-change handling on both sides, a performance harness proving the PRD
success metric (1080p ≥30 fps, end-to-end latency under 120 ms), and canary-based
pcap-audit coverage during an active mirror session. ADR-006 (mirroring path) is finalized
here using this phase's real measurements, gating E62's optional scrcpy alternative.

**Exit criteria**

- [ ] Mirroring sustains 1080p ≥30 fps with p95 end-to-end latency under 120 ms on 5 GHz Wi-Fi (roadmap Phase 6 exit criterion / PRD success metric).
- [ ] pcap-audit with an on-screen canary during mirroring shows zero plaintext occurrences.
- [ ] ADR-006 is marked Accepted with a final decision informed by this phase's measurements.
- [ ] The fragment rule holds on both sides: a 3-fragment unit is accepted; index gap, count change, count 9, interleaved pts and > 8 MiB are rejected with MALFORMED_FRAME (E61-01, E61-03, E61-14).
- [ ] A MirrorRequest alone never starts capture or issues a ticket (E61-12, E61-16).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E61-01 | [protocol] MediaFrame/MediaFormat/KeyframeRequest/RotationChanged messages | task | P0 | M | E60-01, E15-01, E15-02, E01-22 |
| E61-02 | [android] MediaProjection consent flow per session | task | P0 | M | E20-02, E00-20, E00-21 |
| E61-03 | [android] VirtualDisplay + MediaCodec encode pipeline to MediaFrame | task | P0 | M | E61-01, E61-02, E61-13, E60-02, E00-21 |
| E61-04 | [android] HEVC capability negotiation with H.264 fallback | task | P1 | M | E61-03, E61-13, E61-14 |
| E61-05 | [android] Rotation and resolution change handling | task | P0 | M | E61-03, E00-21 |
| E61-06 | [macos] VTDecompressionSession decode pipeline | task | P0 | M | E61-01, E61-14, E60-03, E00-08 |
| E61-07 | [macos] Resizable mirror window + rotation handling | task | P0 | M | E61-06, E00-08 |
| E61-08 | [cross] Mirroring performance harness: fps + end-to-end latency | test | P0 | L | E61-03, E61-06, E61-07, E00-23 |
| E61-09 | [tools] pcap-audit with on-screen canary during mirroring | test | P0 | S | E61-08, E15-06, E15-07 |
| E61-10 | [docs] Finalize ADR-006: mirroring path decision | adr | P0 | S | E02-07, E61-08 |
| E61-11 | [android] Encoder/session teardown and resource cleanup on mirror stop | task | P0 | S | E61-02, E61-03, E60-09, E00-21 |
| E61-12 | [macos] Mirror quick action: Mac request + declined state | story | P0 | S | E22-02, E61-15, E60-03, E60-08, E12-12, E00-26 |
| E61-13 | [android] Encoder configuration builder (CBR, low latency, profile/level, GOP) | task | P0 | S | E61-01 |
| E61-14 | [macos] Annex-B parsing, format description + decoder capability advertisement | task | P0 | M | E61-01, E00-08 |
| E61-15 | [protocol] MirrorRequest/MirrorDeclined messages + vectors | task | P0 | S | E61-01, E15-01, E15-02 |
| E61-16 | [android] MirrorRequest on-phone start prompt | story | P0 | M | E61-15, E61-02, E60-02, E12-11, E00-18, E00-20, E00-21 |

### E62 — Remote input

Mac mouse, scroll and keystroke input, mapped to phone screen coordinates (rotation,
letterboxing) and injected via AccessibilityService gestures, global actions and text edits
(TextEdit insert/deleteBackward/imeEnter and SetText; no raw key events). Input is accepted only
while a user-started, bound mirror session is active, within field ranges and a 120 events/s
token bucket (burst 240), and only while the on-phone indicator (ongoing notification plus a
TYPE_ACCESSIBILITY_OVERLAY badge above app overlays) is attached (invariant 8); anything else is
dropped and logged without content, never injected (AC-06, AC-19). Includes the P2,
ADR-006-gated scrcpy alternative input path.

**Exit criteria**

- [ ] INPUT frames arriving without an active, user-started mirror session are ignored and logged, never injected (roadmap Phase 6 exit criterion).
- [ ] A scripted device-level sequence of taps, swipes, text entry, and global actions all succeed on physical hardware from the Mac mirror window.
- [ ] A 1000 events/s flood injects at most 240 events in any second, out-of-range coordinates are dropped (never clamped), and frames are dropped while the indicator overlay is detached (E62-06, E62-08).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E62-01 | [protocol] input.proto: gestures, global actions, text, session binding | task | P0 | M | E60-01, E15-01, E15-02, E01-22 |
| E62-02 | [android] AccessibilityService opt-in with explanation | task | P0 | M | E62-01, E00-20, E00-21, E00-28 |
| E62-03 | [android] Coordinate mapping (rotation, letterboxing) pure function | task | P0 | M | E62-01 |
| E62-04 | [android] dispatchGesture for taps, swipes, scroll | task | P0 | M | E62-02, E62-03, E00-20, E00-21 |
| E62-05 | [android] performGlobalAction + ACTION_SET_TEXT | task | P0 | M | E62-02, E00-20, E00-21 |
| E62-06 | [android] Input authorization gate + persistent on-phone indicator | task | P0 | M | E62-04, E62-05, E60-09, E61-02, E12-11, E00-20, E00-21 |
| E62-07 | [macos] Mouse/keyboard/scroll capture in mirror window | task | P0 | M | E62-01, E61-07, E00-08 |
| E62-08 | [tools] Security test: input authorization (AC-06) | test | P0 | M | E62-06, E15-08, E15-15, E15-17 |
| E62-09 | [cross] End-to-end remote input device test | test | P0 | M | E62-04, E62-05, E62-06, E62-07, E00-23 |
| E62-10 | [android] Alternative input path via scrcpy (P2, gated on ADR-006) | task | P2 | L | E61-10, E15-08, E00-23 |

## Phase 7 — Extras and hardening

### E70 — Key rotation

Replace a device's long-term identity key without re-pairing, as key hygiene, not compromise
recovery (a suspected compromise is unpair + re-pair). Over an authenticated control session a
device sends KeyRotation{newSpkiDer, sigOldKey, sigNewKey}, both ECDSA P-256 signatures over
"tandem-rotate-v1" || LP(oldSpkiDer) || LP(newSpkiDer) || LP(cb), bound to the session channel
binding (the new-key signature is proof of possession). The peer verifies against its current
primary pin, rejects DUPLICATE_KEY and (while the Mac pairing window is open or a rotation is
pending) ROTATION_UNAVAILABLE, swaps pins atomically in one trust-store record (grace fields added
by migration), and keeps the old key as a grace pin until the grace session ends or 7 days pass.
The initiator keeps its old key until RotationAck and retries with the pending key. A Mac
rotation is two-phase (decision D-34): the listener switches only after every paired phone has
acked, and each phone keeps the old Mac pin until a handshake presents the new one. Covers
user-initiated and scheduled rotation, failure/rollback, an end-to-end harness test and mitm-lab
scenarios (unauthenticated channel, cross-session replay, duplicate key).

**Exit criteria**

- [ ] A user-triggered rotation on either platform completes; both peers pin the new fingerprint via an atomic single-record swap, and the old pin is purged after one grace session or 7 days, whichever comes first.
- [ ] A scheduled rotation fires automatically only over an authenticated session and defers cleanly when offline.
- [ ] mitm-lab confirms rotation attempted outside an authenticated session is rejected with no trust-store change.
- [ ] A KeyRotation replayed from another session is rejected INVALID_SIGNATURE, a newSpki equal to any existing pin DUPLICATE_KEY, and any rotation while the Mac pairing window is open ROTATION_UNAVAILABLE, trust stores unchanged (E70-04, E70-05, E70-09).
- [ ] With two paired phones, a Mac rotation switches the listener only after both acked, and neither phone is ever locked out (E70-03, E70-04).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E70-01 | [protocol] rotation.proto: KeyRotation, RotationAck, RotationReject | task | P0 | M | E01-10, E01-14, E01-16, E15-01, E15-02, E01-01, E01-02, E03-04 |
| E70-02 | [android] Initiate rotation: generate new key + sign with old key | task | P0 | M | E70-01, E10-01, E10-02, E10-03, E10-15, E12-11, E00-21 |
| E70-03 | [macos] Initiate rotation: generate new key + sign with old key | task | P0 | M | E70-01, E10-05, E10-06, E10-08, E10-16, E12-12, E14-02 |
| E70-04 | [android] Receive + verify KeyRotation, pin new key with grace period | task | P0 | M | E70-01, E13-02, E12-11, E13-03, E00-18 |
| E70-05 | [macos] Receive + verify KeyRotation, pin new key with grace period | task | P0 | M | E70-01, E13-06, E12-12, E13-07, E14-02, E00-24 |
| E70-06 | [android] User-initiated rotation UI | story | P0 | S | E70-02, E00-20 |
| E70-07 | [android] Scheduled rotation | task | P0 | M | E70-02, E00-18 |
| E70-08 | [android] Rotation failure and rollback handling | task | P0 | M | E70-02, E00-18, E12-11 |
| E70-09 | [tools] mitm-lab: rotation over unauthenticated channel rejected | test | P0 | S | E70-04, E70-05, E15-08 |
| E70-10 | [cross] End-to-end rotation: JVM client and real Mac server (E15-15) | test | P0 | M | E15-15, E70-02, E70-03, E70-04, E70-05, E70-08, E70-13 |
| E70-11 | [macos] User-initiated rotation UI | story | P0 | S | E70-03, E00-26 |
| E70-12 | [macos] Scheduled rotation | task | P0 | M | E70-03, E00-24 |
| E70-13 | [macos] Rotation failure and rollback handling | task | P0 | M | E70-03, E00-24, E12-12 |

### E71 — Hardening: fuzz campaigns, external SPEC review, release audit

Final security hardening pass before release: 24-hour fuzz campaigns per parser target with a
fix-found-crashes process, an external review of docs/protocol/SPEC.md, and the full release
security audit -- a full-feature canary pcap-audit run, nmap plus the complete mitm-lab suite, an
entitlement/manifest review, a dependency/SBOM scan, signed release builds, and a network egress
audit proving the apps talk only to each other.

**Exit criteria**

- [ ] Every fuzz target completes a clean 24-hour run with zero unresolved crashes.
- [ ] The full-feature pcap-audit canary run and the complete mitm-lab suite both pass.
- [ ] nmap against the phone shows zero open ports.
- [ ] Release builds are signed for both platforms.
- [ ] The egress audit shows only phone<->Mac flows on the Tandem port on both platforms (E71-14).
- [ ] SBOM scan has zero unwaived high/critical findings and the license gate passes on the release trees (E71-10).
- [ ] The entitlement/manifest audit and the E00-30 scan pass on the signed artifacts (E71-09).
- [ ] The release audit checklist (every PRD security-test row, invariants 1-8, AC-01..AC-20 and every decision in docs/planning/decisions.md, each with linked evidence) is approved before the v1 tag (E71-12).

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E71-01 | [tools] Fuzz target: frame length-prefix parser (24 h campaign) | test | P0 | M | E15-13, E15-14 |
| E71-02 | [tools] Fuzz target: Envelope protobuf decoder (24 h campaign) | test | P0 | M | E15-13, E15-14 |
| E71-03 | [tools] Fuzz target: QR pairing payload parser (24 h campaign) | test | P0 | M | E15-13, E14-03 |
| E71-04 | [tools] Fuzz targets: per-domain message decoders, Android Jazzer (24 h each) | test | P0 | M | E15-13, E23-01, E30-01, E31-01, E40-01, E41-01, E50-01, E51-01, E52-01, E60-01, E61-01, E62-01, E70-01 |
| E71-05 | [docs] Fix-found-crashes triage process | doc | P0 | S | E71-01, E71-02, E71-03, E71-04, E71-13 |
| E71-06 | [docs] External review of SPEC.md | doc | P0 | M |  |
| E71-07 | [tools] Release security audit: full-feature canary pcap-audit | test | P0 | M | E15-07, E15-17, E60-06, E61-09, E50-11, E51-08, E52-09 |
| E71-08 | [tools] Release security audit: nmap + full mitm-lab suite | test | P0 | M | E15-09, E15-10, E15-11, E15-12, E60-05, E62-08, E70-09, E15-20 |
| E71-09 | [tools] Release security audit: entitlement + manifest review | test | P0 | M | E22-04, E15-07, E00-11, E00-28, E00-30 |
| E71-10 | [tools] Dependency / SBOM scan | task | P0 | M | E00-11, E00-29 |
| E71-11 | [ci] Release build signing | task | P0 | M | E00-11 |
| E71-12 | [docs] Release security audit checklist and sign-off | doc | P0 | S | E71-05, E71-06, E71-07, E71-08, E71-09, E71-10, E71-11, E71-14, E15-20, E00-29, E00-30, E15-23 |
| E71-13 | [tools] Fuzz targets: per-domain message decoders, macOS libFuzzer (24 h each) | test | P0 | M | E15-14, E23-01, E30-01, E31-01, E40-01, E41-01, E50-01, E51-01, E52-01, E60-01, E61-01, E62-01, E70-01, E61-14 |
| E71-14 | [tools] Release audit: network egress audit (the apps talk only to each other) | test | P0 | M | E71-07, E14-23, E00-23 |

### E72 — Extras (F-10.x: media control, DND sync, USB, multi-Mac)

The v2+ extras capability from the PRD, prioritized P2 and only taken up if there is time
after Phases 5 and 6 land cleanly. Each feature begins with its own design note or ADR
before any implementation issue, per the PRD's "decide in ADR first" guidance for F-10.4
and the general caution warranted by USB transport touching the transport abstraction.

**Exit criteria**

- [ ] Each F-10.x item has an accepted design note or ADR before any code is written.
- [ ] Any implemented P2 item passes its own conformance/acceptance tests without touching invariant 1, 2, or 4 guarantees.

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E72-01 | [docs] Design note: media control (F-10.1) | spike | P2 | S | E30-02 |
| E72-02 | [android] Media control: MediaSession bridge + media-control proto (F-10.1, P2) | task | P2 | M | E72-01, E12-11 |
| E72-03 | [docs] Design note: Focus/DND sync (F-10.2) | spike | P2 | S |  |
| E72-04 | [android] Focus/DND sync: apply interruption filter + focus proto (F-10.2, P2) | task | P2 | S | E72-03, E12-11 |
| E72-05 | [docs] Design spike: USB transport (F-10.3, AOA vs. adb forward) | spike | P2 | M | E12-11, E12-12 |
| E72-06 | [android] USB transport (F-10.3, P2) | task | P2 | M | E72-05, E12-11, E00-19 |
| E72-07 | [docs] ADR: multi-Mac support (F-10.4, resolves Appendix C.2) | adr | P2 | M | E12-08, E12-09 |
| E72-08 | [macos] Media control: now-playing display + transport controls (F-10.1, P2) | task | P2 | S | E72-02, E12-12, E00-26 |
| E72-09 | [macos] Focus/DND sync: Focus-state sender (F-10.2, P2) | task | P2 | S | E72-04, E12-12 |
| E72-10 | [macos] USB transport (F-10.3, P2) | task | P2 | M | E72-05, E12-12, E00-25 |

### E73 — Manual pairing ADR (F-2.2)

Pairing without a camera, deferred to v2+ per the PRD. Gated entirely on an accepted ADR
that specifies a commitment-based short authentication string (SAS) of at least 6 digits,
compared on both screens -- explicitly never a raw fingerprint-prefix check, which is the
exact 32-bit-prefix weakness observed in the LinkMyMac reference (PRD Appendix A).
Implementation issues are P2 and do not start before the ADR is accepted.

**Exit criteria**

- [ ] The ADR is accepted, specifying SAS length, commit-then-reveal ordering, and explicit rejection of fingerprint-prefix comparison.
- [ ] If implemented, brute-force and downgrade mitm-lab scenarios both fail closed.

| ID | Title | Type | Pri | Size | Depends on |
|---|---|---|---|---|---|
| E73-01 | [docs] ADR: manual pairing with commitment-based SAS | adr | P1 | M | E14-16, E02-05 |
| E73-02 | [protocol] manual-pairing.proto (P2, gated on E73-01) | task | P2 | M | E73-01, E15-01, E15-02 |
| E73-03 | [android] Manual pairing implementation (P2, gated on E73-01) | task | P2 | L | E73-02, E13-02, E12-11 |
| E73-04 | [macos] Manual pairing implementation (P2, gated on E73-01) | task | P2 | L | E73-02, E13-06, E12-12, E14-02 |
| E73-05 | [tools] mitm-lab: manual pairing brute-force + downgrade scenarios (P2, gated) | test | P2 | M | E73-03, E73-04, E15-08 |

---

**Totals:** 28 epics, 392 issues (P0: 341, P1: 35, P2: 16)
