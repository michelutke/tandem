# TLS stack fallback decision criteria

Backlog: `docs/planning/backlog/phase-0.yaml` id `E03-06` (GitHub #96). Depends on E03-01.
Feeds ADR-003 (E02-04, `docs/adr/ADR-003-mtls-vs-noise.md`, not yet written) and is the trigger
document E12 (Phase 1 secure-transport implementation) checks against if production code hits
unexpected TLS-stack behavior. Exists regardless of whether E03-05 (swift-nio-ssl fallback) or a
future Android bundled-stack spike ever ran — see `docs/planning/backlog/phase-0.yaml` line 2098.

**Owner of the revisit decision:** the project owner — the same authority that accepts ADR-003
itself (D-40: SPEC.md/decisions.md are the owner's decisions, not delegated). Any trigger below
being met is necessary but not sufficient to switch stacks; it obligates the owner to review the
evidence and record a new decision row (or an ADR-003 amendment), not to switch automatically.

Current state per the Phase 0 spikes:

| Platform | Stack (ADR-003 default) | Spike | Result |
|---|---|---|---|
| macOS | `Network.framework` (`NWListener`/`NWProtocolTLS`) | E03-01 (`nwlistener-mtls.md`) | **GO**, one app-level follow-up (ALPN-absence check) |
| macOS fallback | swift-nio-ssl | E03-05 (`swift-nio-ssl-fallback.md`) | Not executed — not needed |
| Android | Platform `SSLSocket`/Conscrypt + AndroidKeyStore | E03-03 (`android-sslsocket-keystore.md`) | **GO**, contingent on `DIGEST_NONE`; StrongBox/TEE still a physical-device manual gate |
| Channel binding | RFC 9266 exporter (D-15) | E03-04 (`channel-binding.md`, in progress on another branch) | macOS half proven in E03-01 §9; Android/overall outcome pending |

## macOS: `Network.framework` → swift-nio-ssl / BoringSSL

| # | Trigger (observable symptom) | Threshold | Reproduction | Evidence this is a real risk, not hypothetical | Detecting issue |
|---|---|---|---|---|---|
| M1 | `verify_block` completes *after* the connection has already reached `.ready`, or after any application data is delivered | Observed in **>= 1 of 10** handshakes | Re-run `spikes/e03-01-nwlistener/Scripts/run-experiments.sh` §8's ordering check (or the equivalent assertion in E12-01/E12-02's unit tests) against the production `core/transport` listener | E03-01 §8 found verify-before-ready holds in 60+ runs but is a structural/API-contract inference, not a documented guarantee from Apple; a future OS update could change ordering silently | E12-02 (verify-block unit tests); E15-10 (mitm-lab certificate-abuse scenarios) |
| M2 | A session-resumption ticket or 0-RTT-eligible session is issued even with `sec_protocol_options_set_tls_tickets_enabled(false)` and resumption disabled | **>= 1 of 20** connections in `openssl s_client -sess_out`/`-sess_in` (or the E12-03 equivalent) shows a `NewSessionTicket` or `Reused` | `openssl s_client -sess_out ticket.pem` against the production listener, then `-sess_in ticket.pem` on reconnect; check for `Reused` | E03-01 §6 recorded 0/10 tickets with tickets both off and explicitly on; a stack regression here would silently reintroduce the PSK/0-RTT class D-19 explicitly excludes | E12-03 (disable resumption/0-RTT); E15-11 (mitm-lab downgrade/resumption/0-RTT scenarios) |
| M3 | A client presenting **no ALPN extension** is still accepted (`alpn=none`) by the time application data flows, i.e. the mandatory app-level `negotiatedALPN == "tandem/1"` check (E03-01's required follow-up) does not close the gap in the real listener | **>= 1 of 10** connections with no ALPN offered reaches a state where non-VersionHello bytes are processed | `openssl s_client -connect <host>:<port> -tls1_3 -cert ... -key ...` with no `-alpn` flag against `core/transport`'s production listener | E03-01 §5: this is a *known, already-diagnosed* stack gap (Network.framework enforces mismatched ALPN but not absent ALPN); this trigger fires only if the required app-level fix is missing or broken in production code, not if the stack itself regresses | E12-01 (VersionHello/ALPN wiring); E15-11 (protocol-version/downgrade scenarios) |
| M4 | Client-cert rejection (bad pin, missing cert, wrong key) surfaces to production code only as an indistinguishable generic error, preventing D-20's required close codes (`PROTOCOL_TIMEOUT`, `LIMIT_EXCEEDED`) or D-19's fail-closed logging from being applied correctly | Any one of: unpinned-cert, no-cert, and TLS-1.2-downgrade rejections cannot be told apart by `core/transport`'s error handling in a code review or test, across **all** of E15-10's certificate-abuse scenarios | Run E15-10's mitm-lab suite (unknown/wrong/swapped cert) against the production listener and confirm each scenario maps to a distinct, loggable outcome | E03-01 recorded distinguishable errors only at the raw `sec_protocol`/POSIX level (e.g. `-9808`); nothing yet confirms `core/transport` preserves that distinction up through its own error types | E15-10 (mitm-lab certificate-abuse scenarios); E12-18 (admission control, close codes) |

If any of M1–M4 is confirmed in production code (not just theorized), reopen E03-05 (swift-nio-ssl
fallback, currently "not executed") rather than re-running E03-01 from scratch — E03-05's
acceptance criteria are already written as "E03-01's criteria verbatim."

## Android: platform Conscrypt (`SSLSocket` + AndroidKeyStore) → bundled Conscrypt/BoringSSL

| # | Trigger (observable symptom) | Threshold | Reproduction | Evidence this is a real risk, not hypothetical | Detecting issue |
|---|---|---|---|---|---|
| A1 | An AndroidKeyStore key generated with the mandatory `setDigests(DIGEST_SHA256, DIGEST_NONE)` fix (E03-03) still fails TLS 1.3 client-cert handshakes with the same opaque `SSLHandshakeException: I/O error` on a real OEM build | **Any** matrix device in `docs/testing/device-matrix.md` fails after the fix is applied, where the emulator baseline was 10/10 pass on all three AVDs | E14-18 (Keystore client-auth device matrix test); manually, `spikes/e03-03-keystore-sslsocket/scripts/run-spike.sh <device>` adapted to a physical device | E03-03's root cause (Conscrypt signs `CertificateVerify` with `NONEwithECDSA`, requiring `DIGEST_NONE` at key-gen time) was isolated on emulators only; an OEM Keystore/Conscrypt fork could still reject the same key differently | E14-18 (device matrix test); E10-01 (Keystore key generation) |
| A2 | A physical device's TEE-backed (non-StrongBox) handshake p95 exceeds **300 ms**, or a StrongBox-backed device exceeds **1000 ms**, over 10/10 and 20/20 runs (D-48's thresholds), on a device where TEE is the fallback tier | Threshold breach on **any** matrix device per D-48 | E14-18's latency measurement, same harness as E03-03's `[13,13,...]`-style latency arrays but on physical hardware | E03-03 only measured `SOFTWARE`-tier emulators (p95 18–52 ms); no physical StrongBox/TEE device has been tested yet, so D-48's thresholds are unverified against real hardware | E14-18 (device matrix test) |
| A3 | `android.net.ssl.SSLSockets.exportKeyingMaterial` (channel-binding exporter, API 31+) is unavailable or returns a value that does not match `openssl -keymatexport` on any tested API 31+ matrix device | Byte mismatch, or an unexpected `UnsupportedOperationException`, on **any** API 31+ matrix device | E14-18/E03-04's exporter-match check (`diff android.txt openssl.txt`) run on physical API 31+ hardware | E03-03 confirmed byte-exact matches only on two API 34 emulators; no OEM variance data exists yet, and API 29–30 devices structurally cannot use this path at all (already the trigger for D-15's in-band-challenge fallback, not a stack-switch trigger) | E03-04 (channel-binding outcome); E15-21 (JVM harness cross-checks) |
| A4 | The custom `X509TrustManager` SPKI pin check, or the TLS-1.3-only restriction, is bypassable or silently downgraded on an OEM Conscrypt build (e.g. a TLS 1.2 handshake completes despite `SSLParameters.setProtocols(["TLSv1.3"])`) | **>= 1 of 10** downgrade attempts succeeds on any matrix device | E15-11 (mitm-lab downgrade scenarios) run against the physical device matrix, mirroring E03-03's `TLS1.2 server correctly refused` check | E03-03 confirmed TLS 1.2 rejection only on three emulator AVDs, all using the same AOSP Conscrypt build; OEM TLS stacks are the PRD's own named risk ("Keystore-backed keys with SSLSocket client auth behave differently across OEMs" — PRD risks table) | E15-11 (mitm-lab downgrade/protocol-version scenarios); E14-18 |

If any of A1–A4 is confirmed on physical hardware (the manual gate both E03-03 and D-48 already
flag as open), the fallback is a bundled TLS stack (e.g. Conscrypt's standalone/BoringSSL-backed
artifact) rather than platform Conscrypt, since AndroidKeyStore integration — not TLS itself — is
the variable most likely to differ by OEM.

## Cross-cutting: reopen Noise (ADR-003 option b)

| # | Trigger (observable symptom) | Threshold | Reproduction | Evidence | Detecting issue |
|---|---|---|---|---|---|
| X1 | The RFC 9266 exporter fails on **both** platforms in production (not just the still-open Android API 29–30 gap), **and** the in-band-challenge fallback (D-15/D-35) itself fails to bind PairRequest/KeyRotation to a specific TLS session under mitm-lab session-splicing attempts | Both conditions true, per E03-04's final outcome doc and E15-10/E15-11's session-splicing scenarios | `docs/spikes/channel-binding.md` (E03-04) findings, plus a session-splicing scenario added to E15-10/E15-11 | Channel binding via the TLS exporter is the entire justification (D-15) for preferring mTLS+SPKI-pinning's session-binding story over Noise, which binds identity to the handshake transcript natively; losing *both* the exporter and its fallback removes that justification | E03-04 (channel-binding outcome); E70-01 (KeyRotation, which signs over `cb`) |

X1 is deliberately the only Noise-reopen trigger: per-platform stack swaps (macOS/Android tables
above) address implementation-level failures without reopening ADR-003's actual decision (mTLS vs.
Noise). Reopening Noise requires the mTLS *approach* — not a specific stack — to be unable to meet
D-15's channel-binding requirement on any viable implementation.

## Links

- ADR-003 (E02-04, pending): `docs/adr/ADR-003-mtls-vs-noise.md`
- Spikes: `docs/spikes/nwlistener-mtls.md` (E03-01), `docs/spikes/swift-nio-ssl-fallback.md` (E03-05),
  `docs/spikes/android-sslsocket-keystore.md` (E03-03), `docs/spikes/secure-enclave-identity.md`
  (E03-02, unrelated no-go — Keychain key only, not a stack fallback), `docs/spikes/channel-binding.md`
  (E03-04, in progress)
- Decisions: D-15, D-19, D-35, D-40, D-48 (`docs/planning/decisions.md`)
- PRD risks table (`docs/PRD.md`): "Keystore-backed keys with SSLSocket client auth behave
  differently across OEMs"
