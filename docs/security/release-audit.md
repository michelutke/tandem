# Release security audit checklist

E71-12. Run before the v1 tag. Every row names the evidence that proves it and a link to the tool,
procedure or record that produces that evidence. A row is checked only when a run against the release
candidate's build SHA is attached to the release PR. A row without an evidence link fails the checklist
check (`ci: releaseAuditChecklist_rowWithoutEvidenceLink_exitsNonZero`) and every link must resolve
(`ci: releaseAuditLinkCheck_allEvidenceLinks_resolve`).

Release candidate build SHA: ______________________  Date: ______________

Legend: `[ ]` open, `[x]` evidence attached to the release PR. Decisions in
[`decisions.md`](../planning/decisions.md) and [`SPEC.md`](../protocol/SPEC.md) override the PRD.

## 1. Audit tools and campaigns

| Done | Item | Issue | Tool / procedure | Pass condition |
|---|---|---|---|---|
| [ ] | Full-feature canary pcap-audit | E71-07 | [pcap-audit](../../tools/pcap-audit/README.md) | Only TLS 1.3 records on the Tandem port; canary bytes 0 times in capture |
| [ ] | Log-audit with encoded canaries, same session | E71-07, E15-17 | [log-audit](../../tools/log-audit/README.md) | Every canary kind absent raw and encoded from release-build logs |
| [ ] | nmap against the phone, every feature active | E71-08, E15-12 | [nmap-phone-check](../../tools/mitm-lab/nmap-phone-check.sh), manual gate `nmapPhoneCheck_pairedPhysicalPhone_zeroOpenTcpPorts` in [manual-gates](../testing/manual-gates.md) | `nmap -p-` shows zero open ports |
| [ ] | Full mitm-lab suite, all phases in one pass | E71-08 | [mitm-lab](../../tools/mitm-lab/README.md) | Zero unexpected acceptances |
| [ ] | mitm-lab pairing abuse | E15-09 | [e15-09-pairing-abuse](../../tools/mitm-lab/e15-09-pairing-abuse) | Replays rejected, 4th attempt rejected, secret expires |
| [ ] | mitm-lab certificate abuse | E15-10 | [e15-10-cert-abuse](../../tools/mitm-lab/e15-10-cert-abuse) | Handshake fails, no application data |
| [ ] | mitm-lab downgrade, resumption, 0-RTT; `openssl s_client -tls1_2` | E15-11, E71-08 | [e15-11-version-scenarios](../../tools/mitm-lab/e15-11-version-scenarios) | Handshake against the Mac listener fails |
| [ ] | mitm-lab pre-auth DoS | E15-20 | [e15-20-preauth-dos](../../tools/mitm-lab/e15-20-preauth-dos) | Caps and deadlines hold, pairing attempts not burned |
| [ ] | mitm-lab authenticated-session flood | E20-20 | [e20-20-auth-flood](../../tools/mitm-lab/e20-20-auth-flood) | Rate caps close with `LIMIT_EXCEEDED` |
| [ ] | mitm-lab discovery hint | E21-06 | [e21-06-discovery-hint](../../tools/mitm-lab/e21-06-discovery-hint) | Hint never a trust input |
| [ ] | mitm-lab media ticket | E60-05 | [e60-05-media-ticket](../../tools/mitm-lab/e60-05-media-ticket) | Missing, reused, expired or foreign ticket rejected |
| [ ] | mitm-lab input authorization | E62-08 | [e62-08-input-auth](../../tools/mitm-lab/e62-08-input-auth) | Input without a user-started mirror session ignored and logged |
| [ ] | mitm-lab key rotation | E70-09 | [e70-09-rotation](../../tools/mitm-lab/e70-09-rotation) | Replay, foreign-key and stolen-key rotation rejected |
| [ ] | Phase audit runner, all expected steps | E15-18, E15-23 | [tools/audit](../../tools/audit/README.md) | No failing or missing step |
| [ ] | Fuzz campaigns, 24 h each, zero findings | E71-01, E71-02, E71-03, E71-04, E71-13 | [fuzzing](fuzzing.md) clean-run record | Every target has a recorded clean run of at least 86 400 s |
| [ ] | Fix-found-crashes process applied, regression corpus replayed | E71-05 | [fuzzing](fuzzing.md) | No open fuzz bug; regression corpus passes smoke runs |
| [ ] | External review of SPEC.md | E71-06 | [SPEC](../protocol/SPEC.md) | Every finding has a resolution; accepted findings applied |
| [ ] | Entitlement and manifest audit, E00-28 / E22-04 hardening, E00-30 test-code scan on signed artifacts | E71-09 | [release-audit tools](../../tools/release-audit/check-android-manifest.rb), [scan-test-code](../../tools/release-audit/scan-test-code.rb) | Allowlist diffs empty in both directions; scan clean |
| [ ] | SBOM and vulnerability scan, license gate | E71-10, E00-29 | [sbom](../../tools/sbom/sbom.rb) | Zero unwaived high or critical findings; every component licensed |
| [ ] | Release build signing verified | E71-11 | [release workflow](../../.github/workflows) | `apksigner verify` and `codesign --verify --deep --strict` pass on both artifacts |
| [ ] | Release signing adds the Communication Notifications capability for Focus sync | E72-09 | [focus-dnd-sync.md](../spikes/focus-dnd-sync.md) | `com.apple.developer.usernotifications.communication` in the signed app's entitlements and in `mac-entitlements.allowlist`; Focus toggles reach the phone |
| [ ] | Network egress audit, emulator and Mac captures | E71-14 | [egress audit](../../tools/pcap-audit/README.md) | Only flows to the paired peer on the Tandem port |
| [ ] | Egress audit, 24 h physical-phone capture | E71-14 | manual gate `androidEgressAudit_physicalPhone24hCapture_onlyMacTandemPortFlows` in [manual-gates](../testing/manual-gates.md) | Only flows to the paired Mac on the Tandem port |
| [ ] | Manual gates for every P0 `manual:` row in phases 1-7 signed off | all | [manual-gates](../testing/manual-gates.md) | Every sign-off table row filled with date, SHA, device, pass |
| [ ] | Canary procedure on a live phone and Mac, all channels | E15-07, E71-07 | manual gate `canaryProcedure_livePhoneMacPairingWithCanaryName_zeroOccurrencesInCapture` in [manual-gates](../testing/manual-gates.md) | 0 canary occurrences in capture and logs |

### Running the aggregated audits (E71-07, E71-08)

Both runners are release-time, owner-run, and print one combined report; they exit non-zero unless every
check passed. Aggregation logic is covered by fixture tests (`ruby tools/release-audit/test/*_test.rb`).

**Full-feature canary audit (E71-07).** Run one session using notifications, clipboard, files, SMS,
contacts, calls and mirroring together, capturing with [pcap-audit](../../tools/pcap-audit/README.md)
`capture.sh` and collecting the release-build logcat and macOS unified log. List every
[log-audit](../../tools/log-audit/README.md) canary kind in a manifest (`kind=canary` per line; kinds are
`REQUIRED_KINDS` in the runner), then:

```sh
ruby tools/release-audit/full-feature-canary-audit.rb --pcap session.pcapng --port <port> \
  --manifest canaries.txt --logcat logcat.txt --unified-log unified.log
```

It runs `tls13_assertion.py`, `media_volume.py`, and `canary_scan.py` plus `log-audit.sh` once per manifest
canary. A manifest missing a kind fails the audit.

**nmap + full mitm-lab suite (E71-08).** With every feature active and the Mac app listening:

```sh
ruby tools/release-audit/network-audit.rb --phone-ip <phone> --mac-host <mac> --mac-port <port> \
  [--target-host <mac> --target-port <port>]
```

It runs [nmap-phone-check](../../tools/mitm-lab/nmap-phone-check.sh), every `tools/mitm-lab/*/scenarios`
directory through [runner.rb](../../tools/mitm-lab/runner.rb) (a missing expected directory fails), and
`openssl s_client -tls1_2` against the Mac listener, which must not negotiate TLSv1.2.

## 2. PRD security-test rows

| Done | PRD row | Evidence | Link |
|---|---|---|---|
| [ ] | No plaintext on the wire | E71-07 pcap-audit report | [pcap-audit](../../tools/pcap-audit/README.md) |
| [ ] | No phone listeners | E71-08 nmap result, E15-12 manual gate | [manual-gates](../testing/manual-gates.md) |
| [ ] | Wrong or swapped certs | mitm-lab e15-10 | [e15-10-cert-abuse](../../tools/mitm-lab/e15-10-cert-abuse) |
| [ ] | Pairing replay and brute force | mitm-lab e15-09 | [e15-09-pairing-abuse](../../tools/mitm-lab/e15-09-pairing-abuse) |
| [ ] | Downgrade attempts | mitm-lab e15-11, `openssl s_client -tls1_2` | [e15-11-version-scenarios](../../tools/mitm-lab/e15-11-version-scenarios) |
| [ ] | Parser robustness | 24 h fuzz run logs | [fuzzing](fuzzing.md) |
| [ ] | Session binding | mitm-lab e60-05 | [e60-05-media-ticket](../../tools/mitm-lab/e60-05-media-ticket) |
| [ ] | Input authorization | mitm-lab e62-08 | [e62-08-input-auth](../../tools/mitm-lab/e62-08-input-auth) |
| [ ] | Canary procedure | E15-07 / E71-07 canary run | [canary procedure](../PRD.md) |

## 3. Security invariants

| Done | Invariant | Evidence | Link |
|---|---|---|---|
| [ ] | 1. No application data before mTLS with a pinned peer | mitm-lab e15-10, e15-20; pcap-audit | [mitm-lab](../../tools/mitm-lab/README.md) |
| [ ] | 2. No plaintext listener, HTTP, WebDAV, legacy or fallback mode | pcap-audit, e15-11 downgrade, E71-09 audit | [release-audit tools](../../tools/release-audit/check-android-manifest.rb) |
| [ ] | 3. Trust bound to SPKI fingerprints only | e15-10, e21-06 discovery hint | [e21-06-discovery-hint](../../tools/mitm-lab/e21-06-discovery-hint) |
| [ ] | 4. Android opens no listening sockets | nmap, E71-14 egress audit, E71-09 manifest | [nmap-phone-check](../../tools/mitm-lab/nmap-phone-check.sh) |
| [ ] | 5. Pin mismatch, unknown peer, version mismatch fail closed visibly | e15-10, e15-11 | [e15-11-version-scenarios](../../tools/mitm-lab/e15-11-version-scenarios) |
| [ ] | 6. Constant-time secret comparison; single-use, expiring pairing secrets | e15-09, unit tests | [e15-09-pairing-abuse](../../tools/mitm-lab/e15-09-pairing-abuse) |
| [ ] | 7. Release logs free of secrets and content | E71-07 log-audit | [log-audit](../../tools/log-audit/README.md) |
| [ ] | 8. Remote input only in a user-started mirror session | e62-08 | [e62-08-input-auth](../../tools/mitm-lab/e62-08-input-auth) |

## 4. Attack and abuse cases

| Done | Case | Evidence | Link |
|---|---|---|---|
| [ ] | AC-01 Active MITM, wrong or swapped certificate | mitm-lab e15-10 | [e15-10-cert-abuse](../../tools/mitm-lab/e15-10-cert-abuse) |
| [ ] | AC-02 Passive eavesdropping | pcap-audit full-feature run | [pcap-audit](../../tools/pcap-audit/README.md) |
| [ ] | AC-03 Pairing replay, brute force, expired secret | mitm-lab e15-09 | [e15-09-pairing-abuse](../../tools/mitm-lab/e15-09-pairing-abuse) |
| [ ] | AC-04 Unpaired probe, TLS 1.2, resumption, 0-RTT | mitm-lab e15-11, openssl | [e15-11-version-scenarios](../../tools/mitm-lab/e15-11-version-scenarios) |
| [ ] | AC-05 Bonjour tracking | unit tests, protocol vectors | [SPEC](../protocol/SPEC.md) |
| [ ] | AC-06 Input without a mirror session | mitm-lab e62-08 | [e62-08-input-auth](../../tools/mitm-lab/e62-08-input-auth) |
| [ ] | AC-07 Parser crash or exploit | 24 h fuzz logs | [fuzzing](fuzzing.md) |
| [ ] | AC-08 Media connection hijack | mitm-lab e60-05 | [e60-05-media-ticket](../../tools/mitm-lab/e60-05-media-ticket) |
| [ ] | AC-09 Lost or stolen phone | integration test, revoke | [threat model](../threat-model.md) |
| [ ] | AC-10 Secrets in logs | log-audit, release-log-check | [log-audit](../../tools/log-audit/README.md) |
| [ ] | AC-11 Debug or test-only protocol path | E71-09 descriptor and proto-schema scan | [release-audit tools](../../tools/release-audit/check-proto-descriptors.rb) |
| [ ] | AC-12 Lost or stolen Mac | unpair integration tests | [threat model](../threat-model.md) |
| [ ] | AC-13 Pre-auth exhaustion | mitm-lab e15-20 | [e15-20-preauth-dos](../../tools/mitm-lab/e15-20-preauth-dos) |
| [ ] | AC-14 UI spoofing via peer strings | conformance vectors, E01-23 | [conformance](../../tools/conformance) |
| [ ] | AC-15 Key rotation abuse | mitm-lab e70-09 | [e70-09-rotation](../../tools/mitm-lab/e70-09-rotation) |
| [ ] | AC-16 Android IPC abuse | E71-09 manifest audit | [release-audit tools](../../tools/release-audit/check-android-manifest.rb) |
| [ ] | AC-17 Local attacker on the Mac | E71-09 entitlement audit | [release-audit tools](../../tools/release-audit/check-macos-entitlements.rb) |
| [ ] | AC-18 Supply chain and telemetry | E71-10 SBOM, E71-14 egress audit | [sbom](../../tools/sbom/sbom.rb) |
| [ ] | AC-19 Paired-peer feature abuse | mitm-lab e20-20, feature cap tests | [e20-20-auth-flood](../../tools/mitm-lab/e20-20-auth-flood) |
| [ ] | AC-20 Evil QR | pairing confirmation-code tests, manual gate | [manual-gates](../testing/manual-gates.md) |

## 5. Planning decisions

One row per entry in [`decisions.md`](../planning/decisions.md) (cycles 1-8 and owner answers). The
evidence for a decision is the `tdd:` tests of its owning issues in the linked backlog file. Mark a row
only after those tests and the matching audit rows above are green on the release candidate.

| ID | Decision | Owning issues | Evidence | Done |
|---|---|---|---|---|
| D-01 | No PHOTOS channel; photo messages ride FILES with per-stream interleaving. | E01-04, E41-01 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-4](../planning/backlog/phase-4.yaml) | [ ] |
| D-02 | No test-only / debug / echo wire message or build flag; canaries use production paths (Phase 1:... | E01-04, E15-07, E71-09 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1-e15](../planning/backlog/phase-1-e15.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-03 | Media uses a second mTLS connection on the same single listener port; no separate media port. | E60-03, E60-06 | [decisions](../planning/decisions.md), [phase-6](../planning/backlog/phase-6.yaml) | [ ] |
| D-04 | Per-app notification allow/deny is managed on the phone only; the Mac shows no list in v1. | E30-04 | [decisions](../planning/decisions.md), [phase-3](../planning/backlog/phase-3.yaml) | [ ] |
| D-05 | Accessibility-based clipboard auto-capture is ADR-only, off by default. | E31-09 | [decisions](../planning/decisions.md), [phase-3](../planning/backlog/phase-3.yaml) | [ ] |
| D-06 | v1 SMS is text only; MMS deferred to v2 pending the real-mix spike; RCS out (no third-party API). | E50-12 | [decisions](../planning/decisions.md), [phase-5](../planning/backlog/phase-5.yaml) | [ ] |
| D-07 | Call log view deferred to v2. | E52 (out of scope) | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-08 | Mac-initiated reconnect hint (Appendix C.3) is decided by ADR from measured reconnect data; no... | E20-13 (data: E20-12) | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-09 | Every story/task/test lists layer: unit_condition_expectedResult tests; eight layers; seams... | SCHEMA.md, `sync_issues.rb` | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-10 | The Mac drives liveness: Mac sends Heartbeat after 15 s idle and declares dead after 45 s; the... | E01-07, E20-05, E20-15, E20-12 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-11 | CompanionDeviceManager presence is a spike plus conditional P1 issue; phase exit does not need CDM. | E20-03, E20-16 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-12 | Mac SMS and contacts stores are GRDB SQLite, 0600, backup-excluded, no app-level encryption... | E50-09, E51-04, E14-13 | [decisions](../planning/decisions.md), [phase-5](../planning/backlog/phase-5.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-13 | One MALFORMED_FRAME wire close code; detailed reason is local only. | E01-05, E01-19, E11-02, E11-04 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-14 | Pairing proof over a length-prefixed transcript "tandem-pair-v1" // LP(macSpkiDer) //... | E01-02, E01-18, E10-12, E10-13 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-15 | Channel binding cb = RFC 9266 TLS exporter (32 bytes) on TandemSession; fallback in-band challenge... | E01-01, E03-01, E03-03, E03-04, E12-01, E12-04 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-16 | 6-digit confirmation code on both screens; Mac default Don't Pair; phone commits only after "Codes... | E01-02, E14-05, E14-08, E14-16 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-17 | PairRejected on the wire is only REJECTED_BY_OWNER or PAIRING_UNAVAILABLE. | E01-02, E01-11, E14-09, E15-09 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-1-e15](../planning/backlog/phase-1-e15.yaml) | [ ] |
| D-18 | Pairing window: one in-flight candidate, PairRequest within 10 s, QR window not... | E01-02, E01-21, E14-01, E14-02, E14-11 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-19 | TLS profile: AEAD suites, ecdsa_secp256r1_sha256, no PSK / 0-RTT / post-handshake auth, ALPN... | E01-01, E12-01, E12-04, E12-05, E15-10, E15-11 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-1-e15](../planning/backlog/phase-1-e15.yaml) | [ ] |
| D-20 | Pre-auth limits: TLS 10 s, Hello 5 s, PairRequest 10 s, MediaHello 5 s; ≤ 8 pre-auth connections, ≤... | E01-22, E12-18, E15-20 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-1-e15](../planning/backlog/phase-1-e15.yaml) | [ ] |
| D-21 | Feature caps: files 64 GiB, ≤ 4 pending offers, ≤ 2 active, auto-accept ≤ 1 GiB; ≤ 8 thumbs in... | E01-22, E30-01, E40-07, E40-18, E41-04, E50-04, E52-05 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-3](../planning/backlog/phase-3.yaml), [phase-4](../planning/backlog/phase-4.yaml), [phase-5](../planning/backlog/phase-5.yaml) | [ ] |
| D-22 | One untrusted-string rule (strip bidi/control/zero-width, NFC, caps, plain-text rendering),... | E01-23, E01-24, E14-21, E14-22 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-23 | Revoke has no fields, affects only the sender's record, accepted only on a trusted Ready session;... | E01-11, E14-15, E14-19, E12-16 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-24 | KeyRotation signs "tandem-rotate-v1" // LP(old) // LP(new) // LP(cb) with old and new key;... | E70-01 … E70-05, E70-08, E70-13 | [decisions](../planning/decisions.md), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-25 | Media ticket never logged or persisted; MediaHello deadline; MediaHello on a pairing candidate rejected. | E01-09, E60-03, E60-08 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-6](../planning/backlog/phase-6.yaml) | [ ] |
| D-26 | MediaFrame fragments ≤ 960 KiB, ≤ 8 per access unit, contiguous, ≤ 8 MiB reassembled; violations... | E61-01, E61-14, E71-13 | [decisions](../planning/decisions.md), [phase-6](../planning/backlog/phase-6.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-27 | Remote input has no raw key events (TextEdit ops), field ranges, 120 events/s,... | E62-01 … E62-08 | [decisions](../planning/decisions.md), [phase-6](../planning/backlog/phase-6.yaml) | [ ] |
| D-28 | Android: backup off, no cleartext / user CAs, export allowlist, immutable explicit PendingIntents,... | E00-28, E20-08, E31-06, E40-11, E71-09 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-2](../planning/backlog/phase-2.yaml), [phase-3](../planning/backlog/phase-3.yaml), [phase-4](../planning/backlog/phase-4.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-29 | macOS: hardened runtime, no cs.* exceptions, data-protection keychain own group, share extension... | E22-04, E10-05, E13-06, E40-22, E31-13 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-4](../planning/backlog/phase-4.yaml), [phase-3](../planning/backlog/phase-3.yaml) | [ ] |
| D-30 | Test-only code never ships: dex / Mach-O symbol / bundle-contents scan on every release build. | E00-30, E71-09 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-31 | Logging: shared sensitive-symbol list, R8 strips Log.v/d/i, no .public values, canary kinds incl.... | E00-14, E00-17, E00-27, E15-17 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1-e15](../planning/backlog/phase-1-e15.yaml) | [ ] |
| D-32 | Supply chain: Gradle verification + locking, SwiftPM resolved-only, SHA-pinned actions, license... | E00-29, E14-23, E14-10, E71-10, E71-14 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-33 | Threat model split: E02-01 network/protocol flows; E02-08 local surfaces, storage, lost Mac, logs,... | E02-01, E02-08 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-34 | Mac-initiated rotation is two-phase: phones store the new Mac key as *pending* and ack; the Mac... | E70-01, E70-03, E70-04, E70-11, E70-13 | [decisions](../planning/decisions.md), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-35 | E03-04 is the single session-binding outcome issue (docs/spikes/channel-binding.md: exporter or... | E03-04 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-36 | Infra first needed later stays in E00 but lands at that phase's start (lands_in_phase): E00-26,... | E00-22, E00-26, E00-28, E00-29, E00-30 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-37 | A P0 issue never depends on a P1/P2 issue, and every phase-exit row cites a P0 issue (validator +... | `sync_issues.rb`, `critical_path.rb` | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-38 | The JVM harness opens the Mac pairing window through a Debug-only launch argument... | E15-22, E14-16, E00-30 | [decisions](../planning/decisions.md), [phase-1-e15](../planning/backlog/phase-1-e15.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-39 | The audit runner discovers tools/<tool>/audit-step.sh by convention; the all-steps check is a... | E15-18, E15-23 | [decisions](../planning/decisions.md), [phase-1-e15](../planning/backlog/phase-1-e15.yaml) | [ ] |
| D-40 | docs/PRD.md is not edited for planning decisions; SPEC.md and this log override it where they conflict. | — | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-41 | Keep the tap (evil-QR defence, D-16); measure < 10 s from scan to code shown, excluding the owner's tap. | E14-05, E14-16, E14-18, UC-03 | [decisions](../planning/decisions.md), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-42 | SPEC + decisions.md only (D-40); optionally one PRD errata line pointing to decisions.md. | PRD, E01-01, E01-02, E70-01 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-43 | Yes, zxing-cpp. | E14-23, E14-10, E00-29, E71-14 | [decisions](../planning/decisions.md), [phase-1](../planning/backlog/phase-1.yaml), [phase-0](../planning/backlog/phase-0.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-44 | Keep; auto-accept setting off by default. | E01-22, E40-07, E40-18, E50-04 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-4](../planning/backlog/phase-4.yaml), [phase-5](../planning/backlog/phase-5.yaml) | [ ] |
| D-45 | Keep (nothing persisted on the phone). | E30-01, E30-16 | [decisions](../planning/decisions.md), [phase-3](../planning/backlog/phase-3.yaml) | [ ] |
| D-46 | Keep; revisit only if the E20-12 overnight gate fails. | E01-07, E20-05, E20-15, E20-12 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-47 | Keep. | E15-13, E15-14, E71-01 … E71-04, E71-13 | [decisions](../planning/decisions.md), [phase-1-e15](../planning/backlog/phase-1-e15.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-48 | Keep; a StrongBox device that fails only on latency may go TEE-only rather than fail ADR-003. | E03-03, E03-04, E02-04, E10-01 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-49 | Keep for v1 (D-12). | E50-09, E51-04 | [decisions](../planning/decisions.md), [phase-5](../planning/backlog/phase-5.yaml) | [ ] |
| D-50 | Keep (D-04). | E30-04, E30-15 | [decisions](../planning/decisions.md), [phase-3](../planning/backlog/phase-3.yaml) | [ ] |
| D-51 | Network type + cellular level only. | E23-02, E23-04 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-52 | Text only unless E50-12 shows > 10 % MMS in the owner's threads. | E50-12, E50-01, E50-07 | [decisions](../planning/decisions.md), [phase-5](../planning/backlog/phase-5.yaml) | [ ] |
| D-53 | Yes (already in E20-08). | E20-08 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-54 | Yes (D-34); the Mac never switches keys silently. | E70-03, E70-11, E70-13 | [decisions](../planning/decisions.md), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-55 | Yes (ui-spec §6); alternatives: link uptime, key age. | E20-17 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-56 | Phone battery. | E22-01 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-57 | seq is uint64, per channel per direction, starting at 1. Regression is defined relative to the... | E01-03, E11-02, E11-04, E11-05, E11-06 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-58 | No dedicated close-notice message exists on the wire. A close code is inferred by the peer only via... | E01-05, E01-01, E01-06, E01-11, E12-16 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-59 | The listening side (the Mac) MUST NOT surface a per-connection UI notification for a close on a... | E01-05, E12-18, E15-20, E12-10 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-1-e15](../planning/backlog/phase-1-e15.yaml) | [ ] |
| D-60 | The phone answers at most one Heartbeat per second; extra Heartbeats are dropped without a reply. | E20-15, E20-20 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-61 | Non-Heartbeat CONTROL frames are capped at 60 per second per session; exceeding the cap closes the... | E01-22, E20-05, E20-20 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-62 | Ring is idempotent while the phone is ringing, and the alarm starts at most twice per 10 s. | E01-22, E23-06, E23-08 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-63 | VersionHello gains a minor field alongside major: VersionHello{major, minor, capabilities}. Only a... | E01-06, E01-12, E12-07, E12-15 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-64 | Credit flow control (E01-04) closes with CREDIT_VIOLATION on a CreditGrant that would exceed the... | E01-04, E11-07, E11-08, E11-13, E11-14 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-65 | Media-ticket validation (E01-09) follows one fixed order — missing/malformed, no match among all... | E01-09, E60-01, E60-03, E60-08 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-6](../planning/backlog/phase-6.yaml) | [ ] |
| D-66 | The Mac counts every Heartbeat it receives from the phone — a reply or an unsolicited one — toward... | E01-07, E01-22, E20-05, E20-20 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-2](../planning/backlog/phase-2.yaml) | [ ] |
| D-67 | Channel binding uses an in-band challenge on every platform and API level: the verifier sends 32... | E03-04, E01-01, E01-02, E01-11, E14-06, E14-07, E70-01 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-68 | The phone dials each literal QR a address in order with a 3 s per-address connect timeout; a... | E01-02, E01-22, E14-05 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-69 | Heartbeat frames are exempt from the pairing-candidate frame-order rule in both directions: a... | E01-02, E01-07, E14-02 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-70 | A pairing-candidate connection burns one of the 3 attempts whenever it closes for any reason other... | E01-02, E01-05, E01-22, E14-02 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-71 | Evil-QR / relay detection is provided by the SPKI pair (macSpkiDer/phoneSpkiDer) in the pairing... | E01-01, E01-02, E03-04 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml) | [ ] |
| D-72 | The PairRequest 10 s deadline (local reason TIMEOUT) sends no PairRejected at all: the connection... | E01-02, E01-05, E01-11, E14-02, E14-09 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-73 | If a pairing-candidate connection closes, or the pairing window/attempt budget is exhausted, while... | E01-02, E14-08 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-74 | RotationChallenge trigger (option (a)): each side sends exactly one unsolicited RotationChallenge... | E01-01, E70-01, E70-02, E70-03, E70-04, E70-05 | [decisions](../planning/decisions.md), [phase-0](../planning/backlog/phase-0.yaml), [phase-7](../planning/backlog/phase-7.yaml) | [ ] |
| D-75 | macOS Keychain access is split by KeychainTarget: production always uses the data-protection... | E10-07, E15-22 | [decisions](../planning/decisions.md), [phase-1](../planning/backlog/phase-1.yaml), [phase-1-e15](../planning/backlog/phase-1-e15.yaml) | [ ] |
| D-76 | The Mac listener's verify-callback .rejected outcome never surfaces a per-connection banner: it is... | E22-10, E12-16, E70 | [decisions](../planning/decisions.md), [phase-2](../planning/backlog/phase-2.yaml), [phase-1](../planning/backlog/phase-1.yaml) | [ ] |
| D-77 | The 16-byte mirror session id carried by input messages (E62-07) is minted by the phone: a random... | Q19, E62-07, E61-15, E62-06 | [decisions](../planning/decisions.md), [phase-6](../planning/backlog/phase-6.yaml) | [ ] |
| D-78 | v1 mirroring is H.264 only; the E61-04 HEVC negotiation stays dormant until a post-v1 Mac decoder-capability field exists... | E61-04, E61-14, E61-15 | [decisions](../planning/decisions.md), [phase-6](../planning/backlog/phase-6.yaml) | [ ] |
| D-79 | Android minSdk 33 (was 29); no pre-33 code paths or READ_EXTERNAL_STORAGE declaration remain... | E00-21, E14-18, E31-05, E41-02, E61-13, E62-05 | [decisions](../planning/decisions.md), [android-permissions.allowlist](../../tools/release-audit/android-permissions.allowlist) | [ ] |
| D-80 | Android declares REQUEST_IGNORE_BATTERY_OPTIMIZATIONS for the direct battery-exemption dialog (owner approved)... | E20-04 | [decisions](../planning/decisions.md), [android-permissions.allowlist](../../tools/release-audit/android-permissions.allowlist) | [ ] |
| D-81 | Android pins material3 1.5.0-alpha29 (pre-release) over the Compose BOM for Material 3 Expressive components (owner request) | E00-31 | [decisions](../planning/decisions.md) | [ ] |
| D-82 | Android opt-in clipboard auto-capture via a separate minimal accessibility service (ADR-007, off by default) | E31-09 | [decisions](../planning/decisions.md), [ADR-007](../adr/ADR-007-accessibility-clipboard-auto-capture.md) | [ ] |

## Owner sign-off

Sign-off is approval of the release PR carrying this checklist, before the v1 tag. The owner signs;
nobody else fills this section.

| Field | Value |
|---|---|
| Release candidate build SHA | |
| Release tag | |
| Open exceptions (issue links, or "none") | |
| Owner name | |
| Signature | |
| Date | |
