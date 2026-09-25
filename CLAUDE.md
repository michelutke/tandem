# Tandem — agent guide

- Read `docs/PRD.md` and `docs/protocol/SPEC.md` before any change to transport, pairing, or crypto.
  **`SPEC.md` and `docs/planning/decisions.md` override the PRD where they conflict** (e.g. pairing
  proof encoding, key-rotation message, heartbeat direction); owner questions still open are in
  `docs/planning/open-questions.md`.
- Backlog lives in `docs/planning/backlog/*.yaml`; GitHub issues are generated from it
  (`ruby tools/planning/sync_issues.rb validate|render|sync`). Edit YAML, not issues. After editing
  dependencies or priorities run `ruby tools/planning/critical_path.rb --write` (roadmap sections)
  and `ruby tools/planning/traceability.rb`. Start work from `docs/planning/roadmap.md` → Start here.
- UI work follows `docs/design/ui-spec.md` (tokens, components, copy, states); visuals in `ui-design.pen`.
- Work is TDD: write the `tdd:` tests listed on the issue first, see them fail, then implement.
- Never edit generated protocol code; change `protocol/proto` and regenerate.

## Security invariants (non-negotiable — if a task seems to require breaking one, stop and ask)

1. No code path may send application data over a socket that has not completed mTLS with a pinned peer.
2. No plaintext listener, no HTTP server, no WebDAV, no "legacy" or "fallback" mode — ever.
3. Trust is bound to SPKI fingerprints only; IP addresses and device IDs are never trust anchors.
4. The Android app opens no listening sockets.
5. Pin mismatch, unknown peer, or protocol version mismatch fails closed with a visible error.
6. Secrets are compared in constant time; pairing secrets are single-use and expire.
7. Logs never contain secrets, message bodies, notification text, or clipboard content in release builds.
8. Remote input is accepted only during a user-started mirror session with an on-phone indicator.

## Clean-room rule

Do not copy code, assets, strings, or protocol structures from LinkMyMac (PRD › Clean-room rule).

## Commands

Run from the repo root. `tools/planning/check_claude_md.rb --run-commands` executes every line of
this block and fails if any exits non-zero.

```sh
(cd android && ./gradlew :app:assembleDebug test detekt ktlintCheck)
macos/test-packages.sh
xcodebuild -project macos/Tandem.xcodeproj -scheme Tandem -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO -quiet
tools/lint/swiftlint-check.sh
ruby tools/lint/swift-package-rules.rb
tools/lint/release-log-check.sh
tools/lint/literal-color-check.sh
(cd protocol && buf lint && buf breaking --against '../.git#branch=main,subdir=protocol')
tools/protocol/check_generated.sh
```

Not wired yet: conformance vectors (`tools/conformance/run.sh`, E15-01…E15-03) and `tools/pcap-audit`
(E15-04). Once they exist, every PR touching `core/*` must include or update tests and pass
`tools/pcap-audit` locally.

## Testing

Every backlog `tdd:` entry is `"<layer>: unit_condition_expectedResult"`. Layers and harnesses:

- `unit` — JUnit5 + Turbine (Android) / Swift Testing (macOS), fakes from `core/testing` / `TandemTestSupport`.
- `conformance` — `tools/conformance` runs `protocol/vectors/` against both codecs.
- `integration` — JVM client against the real Mac server, or in-process loopback with real TLS on localhost.
- `instrumented` — Android emulator via Gradle Managed Devices.
- `ui` — Compose UI tests under Robolectric / XCUITest with DEBUG-only scenario seeding.
- `manual` — physical-device gate, procedure and sign-off in `docs/testing/manual-gates.md`.
- `security` — mitm-lab, pcap-audit, nmap, log-audit.
- `ci` — repo and tooling checks: lint-rule fixtures, buf, schema/manifest/link checks.

Seam rule: time, dispatchers, sockets and keys are injected — `Clock`, `ElapsedRealtimeSource` and
dispatcher qualifiers (E00-18), `ByteStream` (E00-19), `IdentityKeyStore` (E10-15) on Android;
`Clock<Duration>` + `DateProvider` (E00-24), `ByteStreamConnection` (E00-25), `KeychainStore` (E10-16)
on macOS. No `System.currentTimeMillis()`, `Instant.now()`, `Date()`, `Date.now` or hard-coded
`Dispatchers.IO` in `core/*`, `feature/*`, `Tandem*` or `Feature*` main sources (enforced by the
`InjectedClockOnly` detekt rule and the `injected_clock_only` SwiftLint rule).

Robolectric rule: plain JUnit5 unless an Android framework type is unavoidable; then Robolectric (E00-20).
