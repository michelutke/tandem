# Tandem — requirements traceability

Maps every PRD requirement (`../PRD.md`) and every use case / abuse case (`use-cases.md`) to the
backlog issues that implement and verify it. Sections (a) and the ID index in (h) are generated
from the YAML by `ruby tools/planning/traceability.rb` (run it after editing the backlog; `--check`
fails on stale tables or unknown IDs). All other tables are hand-curated mapping judgment:
"implements" means the issue builds the behaviour, "verifies" means its `acceptance`/`tdd`
proves it.

Legend: **impl** = implementing issue(s), **verify** = issue whose tests prove it,
*(device)* = manual device gate per PRD test strategy.

---

## (a) PRD features → issues

Scope column is judgment; the issue list is generated from each issue's `prd:` field.

<!-- BEGIN GENERATED: features -->
| Feature | Scope | Issues citing it (`prd:`) |
|---|---|---|
| F-1.1 | v1 | E01-17, E03-02, E03-03, E10-01, E10-02, E10-03, E10-04, E10-05, E10-06, E10-07, E10-08, E10-09, E10-14, E10-15, E10-16, E14-18, E20-14 |
| F-1.2 | v1 | E10-16, E12-14, E12-17, E13-01, E13-02, E13-03, E13-04, E13-05, E13-06, E13-07, E13-08, E13-09, E13-10, E13-11 |
| F-1.3 | v1 | E70-01, E70-02, E70-03, E70-04, E70-05, E70-06, E70-07, E70-08, E70-09, E70-10, E70-11, E70-12, E70-13 |
| F-2.1 | v1 | E01-02, E01-11, E01-18, E01-21, E01-23, E01-24, E15-09, E15-20, E15-22, E10-10, E10-11, E10-12, E10-13, E14-01, E14-02, E14-03, E14-04, E14-05, E14-06, E14-07, E14-08, E14-09, E14-10, E14-11, E14-16, E14-24, E14-25, E14-17, E14-18, E14-21, E14-22, E14-23, E71-03 |
| F-2.2 | deferred (v2+): ADR E73-01; implementation P2, gated (E73-02..E73-05) | E73-01, E73-02, E73-03, E73-04, E73-05 |
| F-2.3 | v1 | E01-11, E12-14, E12-17, E13-05, E13-09, E14-12, E14-13, E14-14, E14-15, E14-19, E14-20, E14-26, E14-27, E20-19, E20-21, E50-09, E51-04 |
| F-3.1 | v1 | E01-01, E01-06, E01-12, E01-22, E03-01, E03-03, E03-04, E03-05, E15-10, E15-11, E15-15, E15-18, E15-19, E15-20, E15-21, E15-22, E15-23, E12-01, E12-02, E12-03, E12-04, E12-05, E12-06, E12-07, E12-15, E12-08, E12-09, E12-10, E12-16, E12-11, E12-12, E12-13, E12-18, E12-19, E14-18, E21-06 |
| F-3.2 | v1 | E01-03, E01-04, E01-05, E01-10, E01-12, E01-19, E01-22, E15-13, E15-14, E15-18, E15-19, E15-23, E11-01, E11-02, E11-03, E11-04, E11-05, E11-06, E11-07, E11-13, E11-08, E11-14, E11-09, E11-10, E11-11, E11-12, E20-20, E40-15, E71-01, E71-02 |
| F-3.3 | v1 | E01-09, E01-12, E01-22, E60-01, E60-02, E60-03, E60-04, E60-05, E60-06, E60-07, E60-08, E60-09, E61-12 |
| F-3.4 | v1 | E01-07, E01-12, E20-01, E20-05, E20-06, E20-07, E20-10, E20-11, E20-12, E20-13, E20-15, E20-20 |
| F-3.5 | v1 | E01-08, E01-20, E21-02, E21-03, E21-04, E21-05, E21-06, E21-07 |
| F-4.1 | v1 | E00-31, E20-02, E20-03, E20-04, E20-08, E20-09, E20-13, E20-14, E20-16, E20-17, E20-18, E20-19 |
| F-4.2 | v1 | E00-32, E22-01, E22-02, E22-03, E22-04, E22-05, E22-08, E22-09, E22-11, E31-11, E40-10, E61-12, E61-15, E61-16 |
| F-4.3 | v1 | E01-13, E20-17, E23-01, E23-02, E23-03, E23-04, E23-08 |
| F-4.4 | v1 | E01-13, E23-01, E23-05, E23-06, E23-07, E23-08 |
| F-5.1 | v1 | E00-22, E01-14, E01-23, E01-24, E14-22, E30-01, E30-02, E30-03, E30-04, E30-05, E30-06, E30-07, E30-12, E30-13, E30-14, E30-16 |
| F-5.2 | v1 | E00-22, E30-01, E30-07, E30-08, E30-09, E30-13, E30-17 |
| F-5.3 | v1 | E30-01, E30-10, E30-13, E30-17, E30-18 |
| F-5.4 | v1 | E30-01, E30-11, E30-13, E30-15 |
| F-6.1 | v1 | E01-14, E31-01, E31-02, E31-03, E31-04, E31-05, E31-10, E31-11 |
| F-6.2 | v1; accessibility auto-capture is ADR-only, off by default (E31-09) | E31-01, E31-06, E31-07, E31-09, E31-12, E31-13 |
| F-6.3 | v1 | E31-01, E31-04, E31-06, E31-08, E31-10, E31-11, E31-14 |
| F-7.1 | v1 | E01-14, E01-23, E14-21, E40-01, E40-02, E40-03, E40-04, E40-07, E40-08, E40-09, E40-12, E40-14, E40-16, E40-17, E40-18, E40-19, E40-20, E40-23 |
| F-7.2 | v1 | E40-06, E40-10, E40-21, E40-22, E40-24 |
| F-7.3 | v1 | E40-05, E40-11, E40-13 |
| F-7.4 | v1 | E41-01, E41-02, E41-03, E41-04, E41-05, E41-06, E41-07, E41-08, E41-09, E41-10, E41-11 |
| F-7.5 | out of scope v1 (PRD marks v2); recorded in E40 out_of_scope, no issue | — |
| F-8.1 | v1 text SMS; MMS deferred to v2, scope spike E50-12 (Appendix C.4) | E01-14, E01-23, E14-22, E50-01, E50-02, E50-03, E50-07, E50-08, E50-09, E50-10, E50-11, E50-12, E50-13, E50-14 |
| F-8.2 | v1 | E50-01, E50-04, E50-05, E50-06, E50-08, E50-10, E50-11, E50-14 |
| F-8.3 | v1 | E51-01, E51-02, E51-03, E51-04, E51-05, E51-06, E51-07, E51-08, E51-09 |
| F-8.4 | v1; call log view deferred to v2 (E52 out_of_scope) | E01-23, E52-01, E52-02, E52-03, E52-04, E52-05, E52-06, E52-07, E52-08, E52-09 |
| F-9.1 | v1 | E01-14, E61-01, E61-02, E61-03, E61-04, E61-05, E61-08, E61-11, E61-12, E61-13, E61-15, E61-16 |
| F-9.2 | v1 | E61-01, E61-06, E61-07, E61-08, E61-14 |
| F-9.3 | v1 | E62-01, E62-02, E62-03, E62-04, E62-05, E62-06, E62-07, E62-08, E62-09 |
| F-9.4 | ADR-decided: options E02-07, decision E61-10; implementation P2, gated (E62-10) | E61-10, E62-10 |
| F-10.1 | v2+/P2: design note E72-01 gates E72-02 | E72-01, E72-02, E72-08 |
| F-10.2 | v2+/P2: design note E72-03 gates E72-04 | E72-03, E72-04, E72-09 |
| F-10.3 | v2+/P2: design spike E72-05 gates E72-06 | E72-05, E72-06, E72-10 |
| F-10.4 | out of scope v1: ADR only (E72-07, Appendix C.2); implementation is a future epic | E72-07 |
<!-- END GENERATED: features -->

Owner notes for items the review lead flagged:

| Item | Owner(s) |
|---|---|
| F-1.2 `capabilities` / `lastSeen` fields actually written | E12-14 (macOS) / E12-17 (Android) on Ready, read by E14-14 |
| F-3.2 channel set (no PHOTOS channel) | E01-04 decision; E01-14 domain→channel map; E41-01 rides FILES |
| F-3.5 rotating id | spec E01-08, vectors E01-20, advertise E21-02, recognise E21-05, skew E21-07 |
| F-4.2 quick actions | menu E22-02 → Send File E40-10, Push Clipboard E31-11, Find Phone E23-07, Mirror E61-12 (+ E61-15 messages, E61-16 phone prompt) |
| F-5.1 "system noise" list | E30-03 (explicit rule set, `SYSTEM_NOISE.md`), documented in SPEC via E30-01 |
| F-5.4 two different toggles | phone VISIBILITY_SECRET opt-in E30-11; Mac lock-screen hiding E30-15 |
| F-7.2 Finder Services / Share ext / drag-drop | E40-21 / E40-22 / E40-10 |
| F-7.3 share target / SAF picker | E40-11 |
| F-9.2 rotation handling | E61-05 (encoder side), E61-07 (window side) |
| Invariant 5 version-mismatch visible error | E12-07 / E12-15 (Hello), E12-10, E22-07 (Mac), E12-16, E20-09 (phone); mitm-lab E15-11 |
| F-3.4 heartbeat vs. overnight Doze (decided cycle 3: Mac drives liveness, phone replies, phone timer suspended in Doze, elapsedRealtime silence check) | SPEC E01-07; Mac E20-05; Android E20-15; gate E20-12 |
| F-4.1 CompanionDeviceManager presence over Wi-Fi (feasibility unclear) | spike E20-03 → conditional E20-16 (P1); phase exit does not require CDM |
| F-8.1 / F-8.3 Mac at-rest store for SMS + contacts (decided cycle 3: GRDB SQLite, 0600, excluded from backup; not Keychain) | E50-09, E51-04; unpair purge hook E14-13 |
| Close-code naming (one `MALFORMED_FRAME` wire code + local reason) | E01-05, E01-19, E11-02, E11-04 |

---

## (b) Phase exit criteria and roadmap checklist → verifying issues

### Phase 0

| Criterion (PRD roadmap / `roadmap.md`) | Verify |
|---|---|
| Monorepo scaffolded, CI green on empty modules | E00-01, E00-02, E00-07, E00-11 |
| `CLAUDE.md` with invariants and commands | E00-12 |
| `SPEC.md` v1: handshake, pairing, framing, channels, errors, versioning | E01-01, E01-02, E01-03, E01-04, E01-05, E01-06 (+ heartbeat E01-07, discovery E01-08, media ticket E01-09) |
| `.proto` for envelope, pairing, control, status; `buf lint` passes | E01-10, E01-11, E01-12, E01-13, E01-15 |
| Vectors (fingerprint, HMAC, frames, Bonjour id, QR) reviewed | E01-16 (format + review gate), E01-17, E01-18, E01-19, E01-20, E01-21 |
| Threat model + ADR-001…006 accepted | E02-01, E02-02 … E02-07 (ADR-006 "deferred" by design; finalised E61-10) |
| Spikes answered | E03-01, E03-02, E03-03, E03-04 (fallback E03-05, E03-06) |
| Channel-binding outcome recorded and adopted (cycle 5) | E03-04 → E01-01, E01-02, E01-11 |
| SPEC timeouts/limits/caps and untrusted strings; display-string vectors (cycle 4) | E01-22, E01-23, E01-24 |
| Threat model part 2: local surfaces (cycle 4) | E02-08 |
| Test infrastructure and seams ready (added cycle 3) | E00-18, E00-19, E00-20, E00-21, E00-23, E00-24, E00-25; release-log lint E00-17 / E00-27 (E00-26 lands Phase 1, E00-22 lands Phase 3; cycle 5) |

### Phase 1

| Criterion | Verify |
|---|---|
| Pair via QR, reconnect after restarting both apps (UC-03) | E14-16 (on E15-15 harness); device timing E14-18 *(device)* |
| `pcap-audit`: only TLS 1.3, no canary (AC-02) | E15-05, E15-06, E15-07 (Phase 1 injection via PairRequest display name), run by E15-18 (CI subset E15-19) |
| mitm-lab: unknown client cert | E15-10 |
| mitm-lab: wrong server cert | E15-10 |
| mitm-lab: replayed `PairRequest` | E15-09 |
| mitm-lab: expired secret | E15-09 |
| mitm-lab: 4th attempt | E15-09 |
| mitm-lab: proof for different phone key | E15-09 |
| `nmap` against phone: no listeners | E15-12 *(device)* |
| Conformance vectors green on both platforms in CI | E15-01, E15-02, E15-03 |
| Fuzz smoke in CI | E15-13, E15-14 |
| Keystore client-auth device matrix (PRD risk, added cycle 2) | E14-18 *(device)* |
| One-command audit report, CI subset on `core/*` PRs (UC-25, added cycle 2) | E15-18 (runner), E15-23 (all Phase 1 steps, cycle 5), E15-19 |
| Phone commits trust only after "Codes match"; Mac defaults to Don't Pair (AC-20, cycle 4) | E14-05, E14-08, E14-16 |
| Pre-auth DoS fails closed, paired peers unaffected (AC-13, cycle 4) | E15-20, E12-18 |
| QR decoder chosen with zero egress (cycle 4) | E14-23, E14-10 |
| Landed at Phase 1 start: XCUITest, supply chain, release test-code scan (cycle 5) | E00-26, E00-29, E00-30 |
| Unpair / revoke both sides (UC-07) | E14-12, E14-13, E14-15 (macOS), E14-19 (Android), E14-20 (JVM harness) |
| Key-material test seams (JVM fake keystore, Keychain abstraction; added cycle 3) | E10-15, E10-16 |

### Phase 2

| Criterion | Verify |
|---|---|
| Survives Mac sleep/wake, Wi-Fi switch, overnight Doze (UC-04) | E20-12 (Doze *(device)*); mechanisms E20-05 / E20-15 (heartbeat, Mac drives liveness), E20-07, E20-10, E20-11 |
| Reconnect < 5 s p95 | E20-12 |
| Rotating id recognised by paired phone only (AC-05) | E21-05, E21-07, E21-02 (no name in instance), E01-20 |
| Menu bar shows state, battery, errors; launch at login (UC-05) | E22-01, E23-04, E22-07, E22-03, E23-08 |
| Find my phone rings through DND (UC-06) | E23-05, E23-08 |
| Service restarts after process death and reboot | E20-02, E20-08 |
| Android hardening baseline landed (cycle 5, lands Phase 2) | E00-28 |

### Phase 3

| Criterion | Verify |
|---|---|
| Reply to WhatsApp and Signal from the Mac (UC-09) | E30-13 *(device)*; categories/reply E30-17 |
| Dismiss sync both ways (UC-10) | E30-10 (Android), E30-18 (macOS), E30-13 |
| Companion test app landed (cycle 5, lands Phase 3) | E00-22 |
| Notification p95 < 500 ms (UC-08) | E30-14 *(device)* (added cycle 2) |
| No clipboard echo loops; concealed never leaves the Mac (UC-12) | E31-10 (rewritten cycle 2), E31-08 / E31-14, E31-03, E31-13 |

### Phase 4

| Criterion | Verify |
|---|---|
| 4 GB both ways, forced disconnect, SHA-256 matches (UC-16) | E40-14 *(device)*; resume E40-08 / E40-19 |
| Transfer does not delay notifications | E40-15 (uses E30-14 harness), E11-09, E11-10 |
| Photo browser pages 10k library with bounded cache (UC-17) | E41-09 (added cycle 2), E41-11, E41-06 |

### Phase 5

| Criterion | Verify |
|---|---|
| Send and receive SMS from the Mac (UC-18, UC-19) | E50-10; sync E50-13 / E50-14 |
| Incoming call on the Mac < 1 s; answer and hang up (UC-20) | E52-08 *(device)* |
| Place a call from the Mac, SIM choice, background-start fallback (UC-21) | E52-05, E52-07, E50-05, E52-08 |

### Phase 6

| Criterion | Verify |
|---|---|
| ADR-006 decided | E61-10 |
| 1080p ≥ 30 fps, < 120 ms (UC-22) | E61-08 *(device)*; congestion isolation E60-07 |
| `pcap-audit` during mirroring with on-screen canary | E61-09, E60-06 |
| Media connection without / with reused ticket rejected (AC-08) | E60-05; validator E60-08 |
| Input rejected without user-started session (AC-06) | E62-08; negative control E62-09 *(device)* |

### Phase 7

| Criterion | Verify |
|---|---|
| Key rotation (UC-24), incl. two-phase Mac rotation (D-34, cycle 5) | E70-04, E70-05, E70-08, E70-13, E70-09, E70-10; D-34: E70-01, E70-03, E70-04, E70-11 |
| 24 h fuzz per target, no crashes (AC-07) | E71-01, E71-02, E71-03, E71-04, E71-13 (+ triage E71-05) |
| External review of `SPEC.md` | E71-06 |
| Egress audit: apps talk only to each other (AC-18) | E71-14 |
| SBOM / license scan clean | E71-10 |
| Release security audit signed off, one row per `decisions.md` entry (UC-25) | E71-12 (evidence E71-07 … E71-11, E15-23) |
| F-10.x as prioritised; F-2.2 ADR (optional) | E72-01 … E72-10; E73-01 |

---

## (c) PRD security-test table and canary procedure → issues

| Test (PRD test strategy) | Harness / scenario | Unit-level support | Release run |
|---|---|---|---|
| No plaintext on the wire | E15-04, E15-05, E15-06; media path E60-06 | — | E71-07 |
| No phone listeners | E15-12 | E12-04 (`codebaseScan_noServerSocketBindCallsAnywhere`), E00-14 | E71-08 |
| Wrong or swapped certs | E15-10 | E12-02, E12-05 | E71-08 |
| Pairing replay and brute force | E15-09 | E14-02, E14-07, E14-09 | E71-08 |
| Downgrade attempts (TLS 1.2, resumption, 0-RTT, version) | E15-11 | E12-01, E12-03, E12-04, E12-07 | E71-08 |
| Parser robustness | smoke E15-13, E15-14 | E11-02, E11-04 | E71-01 … E71-04, E71-13 |
| Session binding (media ticket) | E60-05 | E60-03, E60-08 | E71-08 |
| Input authorization | E62-08 | E62-06 | E71-08 |
| Pre-auth DoS / deadlines (cycle 4) | E15-20 | E12-18, E14-02, E12-07, E12-15, E60-03 | E71-08 |
| Pin without private key; ALPN; client PSK (cycle 4) | E15-10, E15-11 | E12-01, E12-04, E12-05 | E71-08 |
| App egress only to the peer (cycle 4) | E71-14 | E14-23 (QR decoder), E00-14 / E00-15 (no crash SDK) | E71-14 |
| Test-only code absent from release (cycle 4) | E00-30 | E10-15, E00-26 | E71-09 |

| Canary procedure step | Owner |
|---|---|
| Fresh `TANDEM-CANARY-<random>`, capture, scan | E15-07, E15-06 |
| Phase 1 injection (no feature channels yet) | E15-07: phone display name in `PairRequest.deviceInfo`; no test-only wire path (E01-04, AC-11) |
| Clipboard text | E15-07 step via E31-06 share target; concealed variant E31-10 |
| File containing the canary | E15-07 step via E40-11 share target |
| Notification containing the canary | E15-07 step via companion app `canary` kind, E00-22 (Tandem filters its own, E30-03) |
| Canary on the mirrored screen | E61-09 |
| All steps in one capture | E71-07 |
| Same canaries absent from app logs | E15-17; per domain E30-13, E31-10, E50-11, E51-08, E52-09 |
| One command, single report | E15-18 |

---

## (d) Security invariants → implementing and verifying issues

| # | Invariant (short) | impl | verify |
|---|---|---|---|
| 1 | No app data before mTLS with pinned peer | E12-01, E12-02, E12-04, E12-05, E12-07 / E12-15 (no channel before Hello), E60-08, E60-09, E14-04, E60-02, E60-03, E72-06 | E15-10, E15-11, E12-13, E20-06, E21-06, E60-05, E70-09, E71-07, E71-08 |
| 2 | No plaintext/HTTP/WebDAV/legacy/fallback | E12-01 (single listener), E60-03 (same port), E00-14, E00-15 (server-library denylist), E22-04, E01-04 (no debug path), E00-26 (UI-test hook DEBUG-only) | E15-05, E15-07 (schema scan), E60-06, E71-07, E71-09 |
| 3 | Trust = SPKI fingerprint only | E13-02, E13-06, E12-02, E12-05, E12-14, E12-17, E20-06, E21-05, E60-03, E10-15, E10-16 | E13-10, E13-11, E15-10, E21-06, E14-15, E14-19, E14-20 |
| 4 | Android opens no listening sockets | E12-04, E00-14, E02-03 (ADR-002), E20-13 (rejects phone-side BLE server) | E15-12, E71-08, E71-09 |
| 5 | Pin/unknown/version mismatch fails closed, visible | E11-02, E11-04, E12-07, E12-15, E12-08, E12-09, E12-10, E12-16, E22-07, E20-09, E14-09, E14-17, E10-09 | E15-10, E15-11 (version-mismatch scenario), E12-07 tdd `hello_incompatibleMajorVersion_failsClosedWithVisibleError` |
| 6 | Constant-time compare; secrets single-use, expiring | E10-10, E10-11, E14-01, E14-02, E14-07, E60-03 | E15-09, E14-07 (`verifyProof_comparison_usesConstantTimeHelper`), E60-05 |
| 7 | No secrets/content in release logs | E00-17, E00-27, E12-10, E12-16, E30-02, E30-16, E31-03, E50-04, E50-09 | E15-17, E30-13, E31-10, E50-11, E51-08, E52-09 |
| 8 | Input only in user-started session with indicator | E61-02, E61-12, E62-02, E62-06, E62-10 (only if ADR-006 authorises) | E62-08, E62-09 |

Cycle 4 additions: inv 1 — E01-01 (channel binding, CertificateVerify + pin, ALPN), E14-06 / E14-07 (proof bound to
the session), E70-04 / E70-05 (rotation bound to the session); verify E15-10, E15-11, E70-09.
Inv 2 — E00-28 (cleartext off, no user CAs), E00-30 (no test code ships), E00-29 (supply chain); verify E71-09, E71-14.
Inv 3 — E12-18 (source IP is a throttling key only; `peerAuthorizer_signature_takesNoAddressOrAdmissionInput`).
Inv 5 — E01-22 / E12-18 deadlines and caps fail closed with `PROTOCOL_TIMEOUT` / `LIMIT_EXCEEDED`; verify E15-20.
Inv 6 — E01-02 (length-prefixed transcript, PairRejected oracle collapse), E60-08 (ticket never logged); verify E15-09.
Inv 7 — E00-17 (R8 strips Log.v/d/i, extended symbol list), E00-27 (no `.public` privacy), E15-17 (canary kinds, encoded forms); verify E71-07.
Inv 8 — E62-06 (accessibility-overlay indicator, rate and field limits), E62-01 (no raw key events); verify E62-08.

---

## (e) PRD risks → mitigating issues

| Risk | Mitigation issues |
|---|---|
| Android kills the background service | E20-02, E20-03 (CDM spike) → E20-16 (conditional), E20-04, E20-07, E20-08, E20-14, E20-15 (Doze-aware heartbeat); measured by E20-12 |
| Keystore + `SSLSocket` client auth differ across OEMs | E03-03 (spike), E10-01 (TEE fallback, never exportable), E14-18 (Phase 1 device matrix) |
| Network.framework client-cert / verify-block edge cases | E03-01, E03-05 (swift-nio-ssl), E03-06 (revisit triggers), E02-04 |
| Android background clipboard restrictions | E31-06, E31-07, E31-12 (QS tile capture activity), E31-09 (accessibility opt-in ADR) |
| MediaProjection consent per session | E61-02, E61-12 (phone prompt flow), E61-10 (ADR-006 / scrcpy) |
| Accessibility is a high-privilege surface | E62-02 (minimal config, no key-event flags), E62-06 (overlay indicator, rate limit), E62-01 (no raw key events), E62-08, E31-09 (off by default) |
| Wi-Fi client isolation | E14-17 (pairing hint), E20-09 (reconnect hint), E72-05 / E72-06 (USB) |
| Scope creep | Process: PRD non-goals, E61/E62 out_of_scope, E72 design-note gating (no dedicated issue) |
| Protocol drift between platforms | E01-15 (`buf breaking`), E00-10, E15-01, E15-02, E15-03, E71-06 |

---

## (f) Appendix C open questions → resolving issue

| Question | Resolved by |
|---|---|
| C.1 Secure Enclave key as `sec_identity` | E03-02 (spike), consumed by E10-05 / E10-07 |
| C.2 Multi-Mac: per-Mac connection vs broker | E72-07 (ADR) |
| C.3 Mac-initiated reconnect (BLE hint) without phone listener | E20-13 (ADR, added cycle 2) |
| C.4 MMS / RCS scope from real message mix | E50-12 (spike, added cycle 2) |

---

## (g) PRD success metrics → measuring issue

| Metric | Measured by |
|---|---|
| Only TLS 1.3 on the Tandem port; canary never captured | E15-05, E15-06, E15-07, E60-06, E61-09, E71-07 |
| Every MITM case fails closed | E15-09, E15-10, E15-11, E60-05, E70-09, E71-08 |
| Notification latency p95 < 500 ms | E30-14 (added cycle 2); under load E40-15 |
| Reconnect < 5 s after network change / Mac wake | E20-12 |
| Mirroring 1080p ≥ 30 fps, < 120 ms | E61-08 |

---

## (h) Use cases and abuse cases → issues

### Acceptance-check coverage (hand-curated)

Every acceptance checkbox in `use-cases.md` and the issue whose `acceptance`/`tdd` proves it.

| UC / AC | Acceptance check | Proven by |
|---|---|---|
| UC-01 | Key `AfterFirstUnlockThisDeviceOnly`, non-exportable | E10-05 |
| UC-01 | Relaunch keeps SPKI fingerprint | E10-08, E10-09 |
| UC-01 | No listening socket until identity exists | E12-01 (`listener_noUsableIdentity_neverStartsListening`) |
| UC-01 | Launch-at-login toggle reflects `SMAppService` | E22-03 |
| UC-01 alt | Keychain denied → visible error, no identity, no listener | E10-09, E12-01 |
| UC-02 | Hardware-backed, non-exportable | E10-01, E14-18 |
| UC-02 | Never opens a listening socket | E12-04, E15-12 |
| UC-02 | Skip path on every permission screen except camera | E20-14 |
| UC-03 | < 10 s after scan | E14-16 (harness proxy), E14-18 *(device)* |
| UC-03 | Exactly one new record each side, matching fingerprints | E14-16 |
| UC-03 | Same QR cannot be used twice | E14-02, E15-09 |
| UC-03 | Survives restart of both apps | E14-16 |
| UC-03 alt | Rejected / expired QR / unreachable → distinct phone messages | E14-08, E14-17 |
| UC-04 | Reconnect < 5 s p95 | E20-12 |
| UC-04 | Survives overnight Doze | E20-12 *(device)*; E20-15 (Doze-aware heartbeat), E01-07 |
| UC-04 | Host on reused IP with other key gets no app data | E20-06, E21-06 |
| UC-05 | Status change visible within 2 s | E23-08, E22-01 |
| UC-05 | Pin/version errors visible in menu | E22-07, E12-10 (phone: E12-16) |
| UC-06 | Rings in silent + DND | E23-05 |
| UC-06 | Stop from Mac within 1 s | E23-08 |
| UC-07 | Removed peer's handshake fails | E14-15, E14-19, E14-20, E15-10 (revoked-while-offline) |
| UC-07 | Mac list shows last-seen | E14-14, E12-14, E12-17 |
| UC-07 alt | "This device is no longer paired" | E12-16 |
| UC-08 | p95 < 500 ms | E30-14 |
| UC-08 | Icon once per package+version | E30-05, E30-06 |
| UC-08 | Own and system-noise never forwarded | E30-03 |
| UC-08 alt | Bounded offline buffer | E30-01, E30-16 |
| UC-09 | Reply to WhatsApp and Signal | E30-13, E30-17 |
| UC-09 alt | "No longer available" | E30-08, E30-09 |
| UC-10 | Dismiss < 1 s both ways | E30-10, E30-18 |
| UC-11 | Filter change applies without reconnect | E30-04, E30-15 |
| UC-12 | Concealed never on phone / in logs | E31-03, E31-10 |
| UC-12 | No echo loop | E31-08, E31-14, E31-10 |
| UC-12 alt | > 1 MiB not sent, hint shown | E31-04 |
| UC-13 | All four entry points without accessibility | E31-06, E31-07, E31-12 |
| UC-14 | Filenames sanitised (traversal, hidden, reserved) | E40-02 (vectors), E40-16, E40-17 |
| UC-14 | Partial files never visible | E40-05, E40-06, E40-09, E40-20 |
| UC-15 | Same as UC-14, mirrored | E40-02, E40-16, E40-17, E40-05, E40-06, E40-11, E40-21, E40-22 |
| UC-16 | 4 GB both ways with forced disconnect | E40-14, E40-08, E40-19 |
| UC-16 | Notifications < 500 ms p95 during transfer | E40-15 |
| UC-17 | 10k library without loading all thumbnails | E41-09, E41-11, E41-05 |
| UC-17 | Cache respects size cap | E41-06, E41-09 |
| UC-18 | New SMS visible on Mac < 2 s | E50-10, E50-14 |
| UC-19 | Failure (no signal) reported | E50-04, E50-08 |
| UC-20 | Answer and hang up from Mac | E52-04, E52-08 |
| UC-21 | Works locked/backgrounded or explains | E52-05 |
| UC-22 | 1080p ≥ 30 fps, < 120 ms | E61-08 |
| UC-22 | pcap-audit with on-screen canary | E61-09 |
| UC-22 | Rotation without restart | E61-05, E61-07 |
| UC-22 | Mac request alone never starts capture / ticket | E61-12, E61-15, E61-16 |
| UC-23 | Input without session ignored and logged | E62-06, E62-08 |
| UC-23 | Coordinates correct portrait / landscape / letterboxed | E62-03 |
| UC-24 | Rotation on unauthenticated connection rejected | E70-02, E70-03, E70-09 |
| UC-24 | Old key stops after grace session | E70-04, E70-05, E70-10 |
| UC-25 | One command per tool; CI subset on `core/*` PRs | E15-18, E15-23, E15-19 |
| AC-01 | MITM wrong/swapped cert | E15-10 |
| AC-02 | Passive eavesdropping | E15-05, E15-06, E15-07 |
| AC-03 | Replay, brute force, expired, other key | E15-09 |
| AC-04 | Unpaired probe; TLS 1.2 / resumption / 0-RTT | E15-10, E15-11 |
| AC-05 | TXT only `v=1` + rotating id; no name | E01-20, E21-02, E21-05, E21-07 |
| AC-06 | Input without session | E62-08 |
| AC-07 | Malformed frames; 24 h fuzz | E11-02, E11-04, E15-13, E15-14, E71-01 … E71-04, E71-13 |
| AC-08 | Missing / reused / expired / other session's ticket | E60-05, E60-03, E60-08 |
| AC-09 | Lost phone revoked on Mac; next handshake fails | E15-10, E14-15, E14-20 |
| AC-10 | No secrets/content in logs | E00-17, E00-27, E15-17, E30-13, E31-10, E50-11, E51-08, E52-09 |
| AC-11 | No debug/test-only protocol path in release (added cycle 2) | E01-04, E15-07, E71-09, E00-26 (UI-test hook absent from Release), E00-30 (dex / symbol / bundle scan, cycle 4) |
| AC-12 | Lost/stolen Mac: phone unpairs, never dials it, rejects its key (cycle 4) | E14-20, E14-12, E14-13 + purgers (E30-06, E30-07, E41-06, E50-09, E51-04, E40-05), E02-08 |
| AC-13 | Pre-auth floods / slowloris / idle candidates fail closed; paired peers unaffected (cycle 4) | E15-20, E12-18, E14-02, E12-02, E60-03 |
| AC-14 | Peer strings sanitized and capped; no name-based trust (cycle 4) | E01-23, E01-24, E14-21, E14-22, E14-08, E30-07, E50-07, E52-06 |
| AC-15 | KeyRotation replay / duplicate key / stolen old key / grace TTL (cycle 4) | E70-01, E70-04, E70-05, E70-09, E14-07 |
| AC-16 | Android IPC: exports, URIs, PendingIntents, tapjacking (cycle 4) | E00-28, E40-11, E31-06, E31-12, E20-08, E71-09 |
| AC-17 | Local Mac attacker: QR capture, loopback, share-extension queue (cycle 4) | E14-11, E14-08 (code), E12-18, E40-22, E10-05, E15-20 |
| AC-18 | Supply chain / telemetry: verified deps, no crash SDK, egress only to peer (cycle 4) | E00-29, E00-14, E00-15, E14-23, E71-10, E71-14 |
| AC-19 | Paired-peer feature abuse: caps, rate limits, MMI codes, fragments, input floods (cycle 4) | E01-22, E40-07, E40-18, E41-04, E50-04, E52-05, E61-01, E61-14, E62-06, E62-08 |
| AC-20 | Evil QR: phone commits trust only after on-phone code confirm (cycle 4) | E14-05, E14-16, E14-17 |

### ID index (generated)

<!-- BEGIN GENERATED: use-cases -->
| ID | Count | Issues citing it (`use_cases:`) |
|---|---|---|
| AC-01 | 20 | E01-01, E01-17, E02-01, E02-04, E03-01, E03-02, E03-03, E03-05, E15-08, E15-10, E15-18, E15-23, E12-03, E12-05, E12-10, E12-16, E14-04, E22-07, E71-07, E71-08 |
| AC-02 | 15 | E00-28, E02-01, E02-04, E15-04, E15-05, E15-06, E15-07, E15-18, E15-23, E30-13, E31-10, E60-06, E61-09, E71-07, E71-14 |
| AC-03 | 15 | E01-02, E01-11, E01-18, E01-21, E02-01, E02-05, E15-08, E15-09, E15-23, E14-02, E14-07, E14-09, E71-03, E71-08, E73-05 |
| AC-04 | 30 | E01-01, E01-05, E01-06, E01-22, E02-01, E02-03, E03-01, E03-03, E15-05, E15-08, E15-11, E15-12, E15-18, E15-20, E15-23, E12-01, E12-02, E12-03, E12-05, E12-07, E12-15, E12-10, E12-13, E12-18, E12-19, E13-10, E13-11, E21-06, E22-07, E71-08 |
| AC-05 | 6 | E01-08, E01-20, E02-01, E21-02, E21-05, E21-07 |
| AC-06 | 10 | E02-01, E02-07, E61-10, E61-12, E61-16, E62-01, E62-06, E62-08, E62-09, E62-10 |
| AC-07 | 18 | E01-03, E01-05, E01-10, E01-19, E02-01, E15-01, E15-02, E15-13, E15-14, E11-02, E11-04, E11-11, E11-12, E61-01, E71-01, E71-02, E71-04, E71-13 |
| AC-08 | 6 | E01-09, E02-01, E60-01, E60-03, E60-05, E60-08 |
| AC-09 | 14 | E02-01, E02-08, E15-10, E13-05, E13-09, E13-10, E13-11, E14-12, E14-13, E14-15, E14-19, E14-20, E14-26, E20-21 |
| AC-10 | 10 | E00-17, E00-27, E02-01, E02-08, E15-17, E30-13, E31-10, E50-11, E51-08, E52-09 |
| AC-11 | 8 | E00-30, E01-04, E02-01, E02-08, E15-07, E15-22, E71-09, E71-12 |
| AC-12 | 9 | E02-08, E14-12, E14-13, E14-20, E30-06, E30-07, E40-05, E41-06, E71-12 |
| AC-13 | 15 | E01-01, E01-05, E01-22, E02-01, E03-01, E15-09, E15-20, E12-02, E12-18, E12-19, E14-02, E14-11, E22-10, E60-03, E71-12 |
| AC-14 | 14 | E01-02, E01-11, E01-23, E01-24, E02-01, E14-03, E14-08, E14-21, E14-22, E30-01, E30-07, E50-07, E52-06, E71-12 |
| AC-15 | 12 | E01-01, E02-01, E03-01, E03-03, E14-07, E70-01, E70-02, E70-03, E70-04, E70-05, E70-09, E71-12 |
| AC-16 | 8 | E00-28, E02-08, E20-08, E31-06, E31-12, E40-11, E71-09, E71-12 |
| AC-17 | 11 | E01-02, E02-08, E15-20, E10-05, E12-18, E14-08, E14-11, E22-04, E40-22, E71-09, E71-12 |
| AC-18 | 8 | E00-14, E00-15, E00-29, E02-08, E14-23, E71-10, E71-12, E71-14 |
| AC-19 | 20 | E01-04, E01-22, E02-01, E30-01, E30-06, E30-09, E40-01, E40-07, E40-18, E41-01, E41-04, E50-01, E50-04, E52-01, E52-05, E61-01, E62-01, E62-06, E62-08, E71-12 |
| AC-20 | 9 | E01-02, E01-18, E02-01, E10-12, E10-13, E14-05, E14-08, E14-16, E71-12 |
| UC-01 | 13 | E00-32, E10-01, E10-02, E10-04, E10-05, E10-06, E10-07, E10-09, E10-16, E12-01, E12-04, E22-01, E22-03 |
| UC-02 | 12 | E00-31, E10-01, E10-04, E10-15, E12-04, E14-10, E14-18, E20-02, E20-03, E20-04, E20-14, E20-16 |
| UC-03 | 47 | E00-31, E00-32, E01-02, E01-08, E01-11, E01-21, E02-05, E03-04, E15-15, E15-21, E15-22, E10-03, E10-08, E10-12, E10-13, E12-02, E12-04, E12-05, E12-06, E12-07, E12-15, E12-13, E13-02, E13-06, E14-01, E14-02, E14-03, E14-04, E14-05, E14-06, E14-07, E14-08, E14-10, E14-11, E14-16, E14-24, E14-25, E14-17, E14-18, E14-23, E20-16, E21-02, E73-01, E73-02, E73-03, E73-04, E73-05 |
| UC-04 | 30 | E01-07, E01-12, E03-04, E15-15, E15-21, E15-22, E12-02, E12-04, E12-05, E12-07, E12-15, E12-08, E12-09, E12-13, E14-16, E20-02, E20-03, E20-05, E20-06, E20-07, E20-08, E20-10, E20-11, E20-12, E20-13, E20-15, E20-17, E21-04, E21-05, E21-06 |
| UC-05 | 29 | E01-13, E15-11, E15-12, E10-03, E10-08, E12-01, E12-08, E12-09, E12-10, E12-16, E12-14, E12-17, E13-02, E13-06, E14-14, E20-09, E20-17, E20-18, E22-01, E22-02, E22-07, E22-08, E22-09, E22-11, E23-01, E23-02, E23-03, E23-04, E23-08 |
| UC-06 | 6 | E01-13, E23-01, E23-05, E23-06, E23-07, E23-08 |
| UC-07 | 22 | E01-11, E15-10, E12-16, E12-14, E12-17, E13-02, E13-05, E13-06, E13-09, E14-12, E14-13, E14-14, E14-15, E14-19, E14-20, E14-26, E14-27, E20-19, E20-21, E22-05, E50-09, E51-04 |
| UC-08 | 21 | E00-22, E01-04, E11-01, E11-03, E11-05, E11-06, E11-09, E11-10, E12-11, E12-12, E30-01, E30-02, E30-03, E30-05, E30-06, E30-07, E30-11, E30-12, E30-13, E30-14, E30-16 |
| UC-09 | 8 | E00-22, E01-04, E30-01, E30-07, E30-08, E30-09, E30-13, E30-17 |
| UC-10 | 5 | E30-01, E30-10, E30-13, E30-17, E30-18 |
| UC-11 | 3 | E30-04, E30-11, E30-15 |
| UC-12 | 13 | E11-05, E11-06, E12-11, E12-12, E31-01, E31-02, E31-03, E31-04, E31-05, E31-08, E31-10, E31-11, E31-14 |
| UC-13 | 14 | E11-01, E11-03, E11-05, E11-06, E12-11, E12-12, E31-01, E31-06, E31-07, E31-08, E31-09, E31-12, E31-13, E31-14 |
| UC-14 | 24 | E01-04, E11-05, E11-06, E11-07, E11-13, E11-08, E11-14, E12-11, E12-12, E40-01, E40-02, E40-04, E40-05, E40-07, E40-09, E40-10, E40-13, E40-14, E40-15, E40-16, E40-20, E40-21, E40-22, E40-23 |
| UC-15 | 24 | E01-04, E11-05, E11-06, E11-07, E11-13, E11-08, E11-14, E11-09, E11-10, E12-11, E12-12, E40-01, E40-02, E40-03, E40-06, E40-09, E40-11, E40-12, E40-14, E40-15, E40-17, E40-18, E40-20, E40-24 |
| UC-16 | 5 | E40-01, E40-08, E40-14, E40-15, E40-19 |
| UC-17 | 12 | E01-04, E41-01, E41-02, E41-03, E41-04, E41-05, E41-06, E41-07, E41-08, E41-09, E41-10, E41-11 |
| UC-18 | 17 | E50-01, E50-02, E50-03, E50-07, E50-08, E50-09, E50-10, E50-12, E50-13, E50-14, E51-01, E51-02, E51-03, E51-04, E51-05, E51-07, E51-09 |
| UC-19 | 13 | E50-01, E50-04, E50-05, E50-06, E50-08, E50-10, E50-14, E51-01, E51-02, E51-03, E51-04, E51-05, E51-07 |
| UC-20 | 12 | E51-01, E51-02, E51-03, E51-04, E51-05, E51-07, E52-01, E52-02, E52-03, E52-04, E52-06, E52-08 |
| UC-21 | 11 | E51-01, E51-02, E51-03, E51-04, E51-05, E51-07, E52-01, E52-02, E52-05, E52-07, E52-08 |
| UC-22 | 26 | E01-09, E01-12, E02-06, E02-07, E60-01, E60-02, E60-03, E60-04, E60-07, E60-09, E61-01, E61-02, E61-03, E61-04, E61-05, E61-06, E61-07, E61-08, E61-09, E61-10, E61-11, E61-12, E61-13, E61-14, E61-15, E61-16 |
| UC-23 | 12 | E02-07, E61-10, E61-16, E62-01, E62-02, E62-03, E62-04, E62-05, E62-06, E62-07, E62-09, E62-10 |
| UC-24 | 13 | E70-01, E70-02, E70-03, E70-04, E70-05, E70-06, E70-07, E70-08, E70-09, E70-10, E70-11, E70-12, E70-13 |
| UC-25 | 4 | E15-18, E15-19, E15-23, E71-12 |
<!-- END GENERATED: use-cases -->

---

## Gaps found and fixed (review cycle 2)

31 gaps. "New" = issue added; "amended" = acceptance/tdd/description changed.

1. **PHOTOS channel undefined** (E41-01 used it; F-3.2 / E01-04 list nine channels). Decision: no
   PHOTOS channel, photo messages ride FILES with per-stream interleaving. Amended E01-04, E01-14,
   E41 (scope), E41-01.
2. **Canary Phase 1 injection used a "test-only CONTROL payload"**, i.e. a debug wire path that
   could ship. Replaced by the production `PairRequest.deviceInfo` display name; SPEC now forbids
   debug/echo/test messages. Amended E15-07, E01-04, E71-09; new abuse case AC-11.
3. **Appendix C.3 had no owner.** New E20-13 (ADR, data-driven by E20-12).
4. **Appendix C.4 had no owner.** New E50-12 (spike).
5. **UC-25 had no issue; Phase 7 sign-off unowned.** New E15-18 (runner + CI subset), E71-12
   (checklist sign-off).
6. **F-1.2 `lastSeen` / `capabilities` never written.** New E12-14; E14-14 now depends on it.
7. **Notification latency success metric unmeasured.** New E30-14; E40-15 amended to use it.
8. **UC-17 / Phase 4 10k-library check untested.** New E41-09; E41-05 amended.
9. **UC-02 onboarding unowned** (only battery screen existed). New E20-14.
10. **UC-03 alternate flows and client-isolation risk unowned.** New E14-17; E20-09 amended.
11. **PRD "early device matrix test in Phase 1" missing.** New E14-18.
12. **F-4.2 quick actions: Push Clipboard and Mirror unowned; Send File unwired.** New E31-11,
    E61-12; amended E40-10, E22-02.
13. **F-5.4 Mac lock-screen hiding conflated with VISIBILITY_SECRET.** New E30-15; E30-11
    retitled/clarified; UC-11 clarified.
14. **F-5.1 "system noise" undefined.** E30-03 amended with an explicit rule set.
15. **UC-09 "no longer available" had no wire message.** Amended E30-01, E30-08, E30-09.
16. **UC-08 offline buffer policy unowned.** Amended E30-01, E30-02.
17. **Single-port contradiction** (E60 exit, E60-06, E71-07 spoke of a separate "media port").
    Amended E60 (exit), E60-06, E71-07; E60-03 gains a same-listener check.
18. **AC-08 "other session's ticket" mis-stated as "unauthenticated session".** Amended E60-05,
    E60-03.
19. **E15-08 cited a scenario issue ID removed in the cycle-1 merge.** Now points to E15-09/10/11, E60-05, E62-08, E70-09.
20. **AC-04 0-RTT and invariant-5 version mismatch not covered by mitm-lab.** Amended E15-11.
21. **AC-09 / UC-07 revoked-while-offline phone untested; "no longer paired" message unowned.**
    Amended E15-10, E12-10.
22. **UC-01 "no listener until identity" and Keychain-denied path unowned.** Amended E12-01, E10-09.
23. **Invariant 2 "no HTTP server / WebDAV" had no static enforcement.** Amended E00-14, E00-15.
24. **E31-10 concealed-item check was vacuous** (pcap of an encrypted stream). Rewritten to
    phone-side + log-audit.
25. **UC-04 "IP reused by another key" untested at reconnect.** Amended E20-06.
26. **AC-05: Bonjour instance name could carry the Mac name.** Amended E21-02 (+ residual SRV
    hostname risk note for E02-01).
27. **Small UC acceptance gaps:** UC-12 size hint (E31-04), UC-14 hidden/reserved names (E40-02),
    UC-18 < 2 s (E50-10), UC-01 launch-at-login status (E22-03), UC-05 2 s (E23-08).
28. **UC-03 acceptance (one record each side, < 10 s) not asserted.** Amended E14-16.
29. **AC-10 not tagged on domain log audits.** Tagged E30-13, E31-10, E50-11, E51-08, E52-09;
    AC-05 tagged on E21-02, E21-05.
30. **E30-04 cited a Mac read-only allow-list view no issue builds.** Note corrected (v1: none).
31. **Roadmap graph stale** (E15 shown purely downstream; missing E13/E14/E20/E22 fan-out).
    `roadmap.md` graph regenerated from issue-level `depends_on`.

Not gaps (checked): F-7.5 has no issue by design (v2, recorded in E40 out_of_scope); AC-08 and
F-3.3 are carried by E60-05 after the cycle-1 merge (E15 scope points there).

## Review cycle 3 (TDD readiness)

- Every `tdd:` entry is `"<layer>: unit_condition_expectedResult"` (layers in `README.md` →
  Test layers); `sync_issues.rb validate` enforces format, spike/adr `tdd: []`, doc `ci:`-only,
  and ≥ 1 entry for story/task/test.
- Test infrastructure / seams added: E00-18 … E00-26 (Android core/testing clock + pipe,
  Robolectric/Compose, emulator CI, companion notification app, device matrix + manual gates,
  macOS TandemTestSupport clock + connection pair, XCUITest), E10-15 (`IdentityKeyStore` fake),
  E10-16 (`KeychainStore`).
- Splits (original ID kept for one half): E00-17→E00-27, E11-07→E11-13, E11-08→E11-14,
  E12-07→E12-15, E12-10→E12-16, E12-14→E12-17, E13-10→E13-11, E14-15→E14-19 (+ E14-20),
  E15-18→E15-19, E20-05→E20-15, E20-03→E20-16, E30-02→E30-16, E30-07→E30-17, E30-10→E30-18,
  E31-06→E31-12, E31-08→E31-14 (+ E31-13), E40-02→E40-16/E40-17, E40-07→E40-18, E40-08→E40-19,
  E40-09→E40-20, E40-10→E40-21/E40-22, E40-12→E40-23, E40-13→E40-24, E41-07→E41-10,
  E41-09→E41-11, E50-02→E50-13 (+ E50-14), E51-02→E51-09, E60-03→E60-08, E60-04→E60-09,
  E61-03→E61-13, E61-06→E61-14, E61-12→E61-15/E61-16, E70-06→E70-11, E70-07→E70-12,
  E70-08→E70-13 (+ E70-10), E71-04→E71-13, E72-02→E72-08, E72-04→E72-09, E72-06→E72-10.
- Decisions: heartbeat vs. Doze (E01-07, E20-05, E20-15); CDM presence → spike E20-03 +
  conditional E20-16; Mac SMS/contacts store = GRDB SQLite (E50-09, E51-04) with unpair purge
  hook (E14-13); single `MALFORMED_FRAME` close code + local reason (E01-05, E01-19);
  `PairRejected` defined in E01-11.

## Review cycle 4 (adversarial security review)

New issues (13): E00-28 (Android hardening baseline), E00-29 (supply-chain baseline), E00-30
(release test-code scan), E01-22 (SPEC timeouts / limits / caps), E01-23 (SPEC untrusted peer
strings), E01-24 (display-string vectors), E02-08 (threat model part 2: local surfaces, storage,
logs, CI, supply chain), E12-18 (Mac listener admission control), E14-21 / E14-22
(DisplayStringSanitizer Android / macOS), E14-23 (spike: QR decoder, ML Kit telemetry vs.
zxing-cpp), E15-20 (mitm-lab pre-auth DoS scenarios), E71-14 (release egress audit).
New abuse cases: AC-12 … AC-20 (`use-cases.md`). UC-03 gains the confirmation-code step.

Decisions (owning issue in brackets; each is a row in the E71-12 release checklist):

1. **Pairing proof encoding** — length-prefixed transcript `"tandem-pair-v1" || LP(macSpkiDer) ||
   LP(phoneSpkiDer) || LP(cb)`, `LP = u16be len || bytes`, 91-byte P-256 SPKI DER only; supersedes
   PRD F-2.1 raw concatenation [E01-02, vectors E01-18, helpers E10-12 / E10-13].
2. **Channel binding** (superseded by D-67, cycle 8 — see below) — as decided in cycle 4: RFC 9266
   TLS exporter (`EXPORTER-Channel-Binding`, 32 bytes) exposed as `TandemSession.channelBinding`;
   binds pairing proof, confirmation code and KeyRotation signatures; spikes must confirm
   Network.framework / `SSLSockets.exportKeyingMaterial`; fallback = in-band challenge. **Cycle 8
   update:** following the E03-04 spike, D-67 made the in-band `PairChallenge`/`RotationChallenge`
   challenge the unconditional mechanism on every platform and API level; there is no exporter code
   path and `TandemSession` exposes no `channelBinding` property at all [E01-01, E03-01, E03-03,
   E03-04, E12-01, E12-04, E12-11, E12-12].
3. **Confirmation code + mutual confirm** — 6-digit HMAC-derived code on Mac dialog and phone;
   Mac default button Don't Pair; phone commits only after "Codes match" (evil QR, AC-20)
   [E01-02, E14-05, E14-08, E14-16, E14-17].
4. **PairRejected oracle** — wire reason collapsed to `REJECTED_BY_OWNER` / `PAIRING_UNAVAILABLE`
   [E01-02, E01-11, E14-09, E14-17, E15-09].
5. **Pairing window hardening** — one in-flight candidate, PairRequest within 10 s (idle candidate
   burns an attempt), QR window `sharingType = .none`, no copy/save, "attempts used up" UI, QR `a`
   literal IPs only (≤ 8), `n` ≤ 64 bytes [E01-02, E01-21, E14-01, E14-02, E14-03, E14-11, E12-02].
6. **TLS profile** — AEAD suites, ecdsa_secp256r1_sha256, no PSK / 0-RTT / post-handshake auth
   (Android client too), ALPN `tandem/1`, no SNI, leaf-only P-256 check, validity/KU ignored,
   CertificateVerify always enforced [E01-01, E10-02, E10-06, E12-01, E12-04, E12-05, E15-10, E15-11].
7. **DoS limits** — new close codes `PROTOCOL_TIMEOUT`, `LIMIT_EXCEEDED`; TLS 10 s, hello 5 s,
   PairRequest 10 s, MediaHello 5 s; ≤ 8 pre-auth connections, ≤ 2 per IP; per-IP throttle (never
   a trust input) [E01-05, E01-22, E12-18, E12-07, E12-15, E60-03, E15-20].
8. **Feature caps** — files (64 GiB, ≤ 4 pending offers, ≤ 2 active, auto-accept ≤ 1 GiB,
   BUSY / TOO_LARGE), photos (≤ 8 thumbs), SMS (1 sync in flight, ≤ 1600 chars, ≤ 10 / min),
   calls (digits only: no MMI/USSD), notifications (string / icon caps), credits cap
   [E01-04, E01-22, E30-01, E30-06, E30-09, E40-01, E40-07, E40-18, E41-01, E41-04, E50-01,
   E50-04, E50-13, E52-01, E52-05].
9. **Untrusted strings** — one sanitization rule (bidi / control / zero-width strip, NFC, caps,
   plain-text rendering), vector-tested on both platforms; homoglyphs out of scope because no
   trust decision uses names [E01-23, E01-24, E14-21, E14-22, E14-08, E30-07, E50-07, E52-06].
10. **Revoke** — no fields; affects only the sender's record; accepted only on a trusted Ready
    session (including right after PairAccepted); "no longer paired" never auto-deletes trust
    [E01-11, E14-15, E12-16, E15-09].
11. **Key rotation** — transcript bound to cb, new-key proof of possession, DUPLICATE_KEY,
    ROTATION_UNAVAILABLE during pairing window, atomic single-record pin swap via migration, grace
    pin TTL 7 days, retry with pending key; rotation is not compromise recovery
    [E70-01 … E70-05, E70-08, E70-09, E70-13 (open item)].
12. **Media ticket** — never logged / persisted; MediaHello deadline; pairing-candidate MediaHello
    rejected [E01-09, E60-03, E60-05, E60-08].
13. **Media fragmentation** — MediaFrame fragments ≤ 960 KiB, ≤ 8 per access unit, contiguous,
    ≤ 8 MiB reassembled, violations `MALFORMED_FRAME`; fuzzed [E61-01, E61-03, E61-14, E71-13].
14. **Remote input** — no raw key events (TextEdit ops instead), field ranges, 120 events/s,
    accessibility-overlay indicator above app overlays [E62-01 … E62-08].
15. **Android platform** — backup off, no cleartext / user CAs, export allowlist with BIND_*
    permissions, immutable explicit PendingIntents, tapjacking filter app-wide, denied permissions,
    URI validation (no `file://`, no Tandem-own authority), PROCESS_TEXT / boot receiver validation,
    sensitive clips not auto-sent; FLAG_SECURE not used [E00-28, E20-08, E30-02, E31-06, E31-07,
    E31-12, E40-11, E62-02, E71-09].
16. **macOS platform** — hardened runtime, no cs.* exceptions, data-protection keychain in own
    group, share extension without network or keychain, App Group queue validated (no XPC), phone
    clips flagged sensitive written as Concealed + Transient, unpair purges icons / thumbnails /
    delivered notifications [E22-04, E10-05, E13-06, E40-22, E31-13, E30-06, E30-07, E41-06].
17. **Test code never ships** — dex / Mach-O symbol / bundle-contents scan on every release build
    [E00-30, E00-22, E00-26, E10-15, E15-15, E71-09].
18. **Logging** — extended sensitive-symbol list, R8 strips Log.v/d/i, no `.public` privacy for
    values, canary kinds incl. file names, coordinates, secrets in encoded forms; no third-party
    crash SDK [E00-14, E00-15, E00-17, E00-27, E15-17, E71-07].
19. **Supply chain / telemetry** — Gradle verification metadata + locking, SwiftPM resolved-only,
    SHA-pinned actions, update bot, license gate, dependency registry; QR decoder spike; release
    egress audit [E00-29, E14-23, E71-10, E71-14].
20. **Threat model scope** — E02-01 enumerates every network / protocol flow and cycle-4 row;
    E02-08 covers local surfaces, storage, lost Mac, logs, CI secrets, supply chain [E02-01, E02-08,
    E71-11 signing-secret exposure].

Open items carried to cycle 5: Mac-initiated rotation with several phones (E70-13 note); PRD
F-1.3 / F-2.1 formulas and the "CameraX + ML Kit" stack line are superseded by SPEC / E14-23 but
the PRD text itself is unchanged. Both resolved in cycle 5 (D-34; `decisions.md` supersession column).

## Review cycle 5 (sequencing, critical path, priorities)

- **Tooling:** `tools/planning/critical_path.rb` (longest P0 chain per phase, hotspots, per-track effort,
  generated roadmap sections; `--check` fails on priority inversions, rows of section (b) with no P0 issue,
  or a stale roadmap). `sync_issues.rb validate` now also rejects priority inversions and supports
  `lands_in_phase`.
- **Critical path (P0, days):** Phase 0 8.0 → 7.0, Phase 1 21.5 → 15.5, Phase 2 8.5 → 7.5; others
  unchanged. Details and the changed dependencies are in `roadmap.md` → Critical path.
- **Splits / new issues:** E15-15 → E15-21 (JVM client) + E15-22 (Mac app driver) + E15-15 (join, M);
  E15-18 → E15-18 (runner, no deps) + E15-23 (Phase 1 all-steps gate).
- **Phase placement:** E00-26, E00-29, E00-30 land at Phase 1 start; E00-28 at Phase 2; E00-22 at
  Phase 3 (`lands_in_phase`).
- **Priority fixes (P1 → P0, 19):** E00-26, E01-14, E02-07, E03-02, E13-03, E13-07, E13-10, E13-11,
  E20-08, E22-02, E22-03, E23-08, E41-06, E50-05, E52-07, E70-06, E70-07, E70-11, E70-12. Dropped the
  inverted dependency E03-06 → E03-05 (P2).
- **Session binding:** E03-04 is the outcome issue (`docs/spikes/channel-binding.md`); E01-01, E01-02,
  E01-11, E14-06, E14-07, E70-01 depend on it, with the in-band challenge as the recorded fallback.
- **Decisions:** all cycle 1–5 planning decisions are logged in `decisions.md` (D-01 … D-40); owner
  questions in `open-questions.md`.
- **Epic drift:** summary / scope / exit criteria of 23 epics re-aligned with their issues (cycle 3/4
  additions, E70 superseded by SPEC decisions, E62 no raw key events, E14 confirmation code).
