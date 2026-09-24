# Tandem — planning

Source of truth for the backlog lives in this folder. GitHub issues, milestones, and labels
are generated from it by `tools/planning/sync_issues.rb`. Edit YAML here, then re-sync.

## Structure

| Artifact | Where | GitHub mapping |
|---|---|---|
| Phase | `roadmap.md` | Milestone (`Phase N — …`) |
| Epic | `backlog/phase-*.yaml` → `epic:` | Issue labelled `type:epic`, parent of its issues (sub-issues) |
| Issue (story/task/spike/adr/test/doc) | `backlog/phase-*.yaml` → `issues:` | Issue, sub-issue of its epic, `blocked by` links from `depends_on` |
| Use case / abuse case | `use-cases.md` (`UC-xx`, `AC-xx`) | Referenced from issue bodies |
| PRD feature | `../PRD.md` (`F-x.y`) | Referenced from issue bodies |
| Traceability | `traceability.md` (PRD / use cases → issues) | Not synced; regenerate with `ruby tools/planning/traceability.rb` |

## Epic catalogue

| ID | Epic | Phase |
|---|---|---|
| E00 | Monorepo scaffolding and CI | 0 |
| E01 | Wire protocol: SPEC.md, .proto schema, test vectors | 0 |
| E02 | Threat model and ADR-001…006 | 0 |
| E03 | Phase 0 technical spikes (mTLS on both platforms, Secure Enclave) | 0 |
| E10 | Device identity (keys, self-signed certs, SPKI fingerprints) | 1 |
| E11 | Protocol codec, multiplexer, flow control | 1 |
| E12 | Secure transport (mTLS 1.3 client/server, pinning) | 1 |
| E13 | Trust store and settings storage | 1 |
| E14 | QR pairing, unpair, revoke | 1 |
| E15 | Security test harness (conformance, pcap-audit, log-audit, mitm-lab, fuzz scaffolding) | 1 |
| E20 | Android connection lifecycle (foreground service, heartbeat, reconnect) | 2 |
| E21 | Bonjour discovery with rotating ID | 2 |
| E22 | macOS menu bar agent and connection UI | 2 |
| E23 | Device status and find my phone | 2 |
| E30 | Notification mirroring, actions, replies, dismiss sync | 3 |
| E31 | Clipboard sync | 3 |
| E40 | File transfer (both directions, resumable) | 4 |
| E41 | Photo browser | 4 |
| E50 | SMS read, sync, send | 5 |
| E51 | Contacts sync | 5 |
| E52 | Calls control | 5 |
| E60 | Media connection with ticket binding | 6 |
| E61 | Screen mirroring (capture, encode, decode, render) | 6 |
| E62 | Remote input | 6 |
| E70 | Key rotation | 7 |
| E71 | Hardening: fuzz campaigns, external SPEC review, release audit | 7 |
| E72 | Extras (F-10.x: media control, DND sync, USB, multi-Mac) | 7 |
| E73 | Manual pairing ADR (F-2.2) | 7 |

## Issue conventions

- **ID:** `E<epic>-<nn>` (e.g. `E12-03`). Stable; referenced by `depends_on`.
- **Title prefix:** `[android]`, `[macos]`, `[protocol]`, `[tools]`, `[docs]`, `[ci]`, `[cross]` (touches both apps).
- **Types:** `story` (user-visible behaviour), `task` (technical), `spike` (time-boxed research, output = findings doc), `adr`, `test` (security/integration harness or scenario), `doc`.
- **Priority:** `P0` must for phase exit, `P1` should, `P2` could.
- **Size:** `S` ≤ ½ day, `M` 1–2 days, `L` 3–5 days. Anything bigger is split.
- **TDD:** every `story`/`task`/`test` lists the failing tests to write first (`tdd:`), each as
  `"<layer>: unit_condition_expectedResult"` (format enforced by `sync_issues.rb validate`).
  Layers are listed below.
- **Security invariants:** list the PRD invariant numbers (1–8) an issue touches; reviewers must check them.

## Test layers

Prefix on every `tdd:` entry; tells the implementer which harness to use.

| Prefix | Harness | Infrastructure issue | Runs |
|---|---|---|---|
| `unit:` | JUnit5 + Turbine (Robolectric only for unavoidable framework types) / Swift Testing | E00-04, E00-18, E00-19, E00-20, E10-15 / E00-08, E00-24, E00-25, E10-16 | every PR |
| `conformance:` | `tools/conformance` over `protocol/vectors/` on both codecs | E15-01, E15-02, E15-03 | every PR |
| `integration:` | JVM client ↔ real Mac server on the macOS runner, or in-process loopback (two real sessions, localhost TLS) | E15-15 | every PR (macOS runner) |
| `instrumented:` | Android emulator, Gradle Managed Devices (API 29 + 35) | E00-21, E00-22 | PRs touching `android/**`, nightly |
| `ui:` | Compose UI tests under Robolectric / XCUITest with DEBUG-only scenario seeding | E00-20 / E00-26 | every PR |
| `manual:` | Physical-device gate, procedure + sign-off in `docs/testing/manual-gates.md` | E00-23 | phase exit |
| `security:` | mitm-lab, pcap-audit, nmap, log-audit | E15-04…E15-18 | core/* PRs (subset), phase exit |
| `ci:` | Lint-rule fixtures, buf lint/breaking, schema/manifest/link checks | E00-05, E00-10, E00-11, E01-15 | every PR |

Test seams (production code must accept these so tests can inject fakes): Android `Clock` +
`ElapsedRealtimeSource` + injected dispatchers (E00-18), `ByteStream` (E00-19),
`IdentityKeyStore` (E10-15), `TandemSession` (E12-11); macOS `Clock<Duration>` + `DateProvider`
(E00-24), `ByteStreamConnection` (E00-25), `KeychainStore` (E10-16), `TandemSession` (E12-12).

## Definition of Ready

- [ ] PRD refs, use cases, and dependencies listed
- [ ] Acceptance criteria testable
- [ ] TDD list names concrete, layer-prefixed tests that fail before implementation
- [ ] Seams/fakes the tests need exist or are in `depends_on`
- [ ] Size ≤ L

## Definition of Done (rendered into every issue)

- [ ] Failing tests written first, then made green
- [ ] Acceptance criteria met
- [ ] Conformance vectors pass on both platforms (if protocol/crypto touched)
- [ ] Lint clean (ktlint, detekt / SwiftLint / buf lint)
- [ ] Security invariants listed on the issue re-checked; no logging of secrets or content
- [ ] Docs updated (SPEC.md / ADR / CLAUDE.md) where behaviour changed
- [ ] CI green

## TDD workflow

1. Pick the next unblocked issue in the current milestone.
2. Branch `e12-03-short-name`.
3. Write the `tdd:` tests; see them fail for the right reason.
4. Implement minimum to go green; refactor.
5. PR with `Closes #n`; CI must pass; merge (no rebase).
