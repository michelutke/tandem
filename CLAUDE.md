# Tandem — agent guide

- Read `docs/PRD.md` and `docs/protocol/SPEC.md` before any change to transport, pairing, or crypto.
- Backlog lives in `docs/planning/backlog/*.yaml`; GitHub issues are generated from it
  (`ruby tools/planning/sync_issues.rb validate|render|sync`). Edit YAML, not issues.
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

## Commands (to be wired up in E00)

- Android: `./gradlew :app:assembleDebug test detekt ktlintCheck`
- macOS: `xcodebuild -scheme Tandem test` ; `swiftlint`
- Protocol: `buf lint && buf breaking --against '.git#branch=main'`
- Conformance: `tools/conformance/run.sh`

Every PR touching `core/*` must include or update tests and pass `tools/pcap-audit` locally.
