<!-- E00-13: mirrors the Definition of Done in docs/planning/README.md and the security
     invariants in CLAUDE.md. Keep both lists in sync if either source changes. -->

## Summary

<!-- What changed and why. Link the issue: Closes #n -->

## Definition of Done

- [ ] Failing tests written first, then made green
- [ ] Acceptance criteria met
- [ ] Conformance vectors pass on both platforms (if protocol/crypto touched)
- [ ] Lint clean (ktlint, detekt / SwiftLint / buf lint)
- [ ] Security invariants listed on the issue re-checked; no logging of secrets or content
- [ ] Docs updated (SPEC.md / ADR / CLAUDE.md) where behaviour changed
- [ ] CI green

## Security invariants touched (check all that apply, or none)

- [ ] 1. No application data over a socket before mTLS with a pinned peer completes
- [ ] 2. No plaintext listener, HTTP server, WebDAV, "legacy" or "fallback" mode
- [ ] 3. Trust is bound to SPKI fingerprints only (never IP addresses or device IDs)
- [ ] 4. The Android app opens no listening sockets
- [ ] 5. Pin mismatch, unknown peer, or protocol version mismatch fails closed with a visible error
- [ ] 6. Secrets compared in constant time; pairing secrets are single-use and expire
- [ ] 7. Logs never contain secrets, message bodies, notification text, or clipboard content in release builds
- [ ] 8. Remote input accepted only during a user-started mirror session with an on-phone indicator

## Test plan

<!-- Commands run and their output, or N/A -->
