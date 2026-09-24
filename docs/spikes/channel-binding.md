# Channel binding outcome (E03-04) — the session-binding decision for D-15/D-35

Issue: GitHub #94 / backlog `E03-04` (`docs/planning/backlog/phase-0.yaml`). Branch
`e03-04-e2e-handshake-channel-binding`. Code lives in `spikes/e03-04-e2e/` (throwaway, wires
together E03-01's macOS `NWListener` spike and E03-03's Android `SSLSocket`/`AndroidKeyStore`
spike over a real emulator<->host mTLS 1.3 connection; not shipped).

Per D-35, **this is the single outcome document for session binding**: `E01-01`, `E01-02`,
`E01-11`, `E14-06`, `E14-07` and `E70-01` all consume the decision recorded here rather than
re-deriving it. D-15 already commits to a specific shape ("RFC 9266 TLS exporter on
`TandemSession`; fallback in-band challenge if a stack cannot export") — this spike is the
empirical check of whether that shape actually holds once both platforms' TLS stacks are talking
to each other for real, not just individually (E03-01, E03-03).

## OUTCOME

**Adopted (D-67): (c) in-band challenge everywhere — one code path on every API level and on the Mac.**
The spike proved both primitives; the orchestrator chose (c) over the spike's recommendation (b)
because the security argument below shows the fresh in-session challenge is equivalent to the exporter
against replay and relay *given mutual SPKI pinning* (the phone pins the QR `fp` during pairing, both
sides pin each other afterwards), and one path halves the implementation and test matrix (KISS). The
exporter stays documented here as the stronger primitive to revisit if pinning assumptions ever change.

Spike recommendation (superseded by D-67):

**(b) exporter on API ≥ 31, in-band challenge below.** Two code paths, gated on
`Build.VERSION.SDK_INT >= 31` on Android (macOS always has the exporter available — see E03-01
§9). This confirms D-15's existing design rather than overriding it: both primitives were proven
correct end-to-end in this spike, and nothing found here justifies the disruption of changing an
already-recorded architecture decision. See "Recommendation and reasoning" below for why (a) and
(c) were considered and set aside.

## Go/no-go summary

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Real Android emulator <-> real macOS `NWListener` process, mutual pin verification both directions, TLS 1.3 only, ALPN `tandem/1` | **GO** | §1: 10/10 on `teamorg_api34` (API 34) and separately on `teamorg_api29` (API 29) |
| 2 | Both sides derive byte-identical RFC 9266 exporter values (API 31+) | **GO** | §1: 10/10, SHA-256 of each side's 32-byte exporter compared, all 10 pairs identical |
| 3 | Exporter confirmed unavailable on API 29/30 | **GO** (confirms E03-03's finding, now cross-platform) | §2: `android.net.ssl.SSLSockets.exportKeyingMaterial` returns/asserts `null` 10/10 on `teamorg_api29` |
| 4 | In-band challenge fallback works on API 29 | **GO** | §2: 10/10 challenge/response round trips verified by the macOS listener against the peer's pinned public key |
| 5 | Security trade-off analysis (exporter vs. in-band challenge, relay/MITM given pinning) | done | "Security trade-off" section below |

## Environment

- macOS: same machine/toolchain as E03-01 (macOS 26.5-class, Xcode 26.6, Swift 6.3.3,
  Network/Security frameworks). `spikes/e03-04-e2e/mac` — SwiftPM executable `e2e-mac`, built with
  `swift build -c release` (no external dependencies).
- Android: `teamorg_api34` (Android 14, API 34) and `teamorg_api29` (Android 10, API 29) emulator
  AVDs, headless (`-no-window -no-audio -no-boot-anim -netfast`), reaching the host at `10.0.2.2`
  (which resolves to the host's loopback interface, so the Mac listener binding `127.0.0.1` is
  reachable without any extra network configuration). `spikes/e03-04-e2e/android` — standalone
  Gradle project (AGP 9.4.1, `compileSdk 35`, `minSdk 29`), reusing E03-03's
  `KeystoreIdentity`/`KeystoreKeyManager`/`PinningTrustManager`/`TlsHandshakeClient`.
- Driver: `spikes/e03-04-e2e/scripts/run-e2e.sh <avd-name> <exporter|challenge>` — builds both
  sides, boots the AVD, generates the Android identity first and feeds its real SPKI pin into the
  macOS listener's pin file (`--client-name android-client`), starts the listener, runs the
  relevant instrumented test class, pulls both logs, tears everything down. No login keychain or
  signing identity is used anywhere (ad-hoc/temporary keychain only, inherited from E03-01). Every
  run in this spike ended with the emulator killed and the listener process killed;
  `adb devices` empty and no `emulator`/`qemu-system`/`e2e-mac` process left running afterward
  (verified after each run, see "Cleanup").

## §1 — Experiment 1: cross-platform handshake + exporter match (API 34)

`scripts/run-e2e.sh teamorg_api34 exporter`. `ExporterHandshakeTest.handshake10x_tls13_alpnTandem1_exporterRecorded`
runs 10 fresh `SSLContext`s against the real macOS listener, asserting TLS 1.3 + ALPN `tandem/1`
every time, then reads/exchanges one `hello`/`ack` application-data round trip (see gotcha below),
computes `exportKeyingMaterial("EXPORTER-Channel-Binding", "", 32)`, and asserts it is non-null on
API 31+.

```
$ ./scripts/run-e2e.sh teamorg_api34 exporter
...
com.tandem.spike.e2ehandshake.ExporterHandshakeTest:.
Time: 0.293
OK (1 test)
...
--- comparing exporter_sha256 values ---
MATCH:       10 of 10 pairs identical
```

Sample matched pair (Android logcat / macOS listener log, run 0):
```
android: run=0 latencyMs=33 exporter_sha256=88b7769ee71c405798681f3d0252289dcc609bbfed62ad13a8a24c64c257c840
mac:     EVENT type=ready role=server ... alpn=tandem/1 exporter_sha256=88b7769ee71c405798681f3d0252289dcc609bbfed62ad13a8a24c64c257c840
```
Mutual pin verification is exercised on every one of the 10 runs (Mac's `verify_block` logs
`match=true` against the Android client's real AndroidKeyStore-derived SPKI; Android's
`checkServerTrusted` logs `expected == actual` against the Mac's real SPKI) — this spike does not
re-run the negative/mismatch cases (wrong pin, no cert, TLS 1.2, missing ALPN), since those were
already established per-platform in E03-01 §2-§5 and E03-03's `test03`/`test04`; E03-04's job is
interop, not re-deriving single-platform behavior.

Latencies (ms, Android side, 10 runs, includes the hello/ack round trip):
`[15,17,18,18,19,20,20,23,26,30]`, p50=19, p95=26 — comparable to E03-03's software-keystore
numbers (no StrongBox/TEE available on this emulator, same caveat as E03-03).

Raw logs: `spikes/e03-04-e2e/results/teamorg_api34-exporter/`.

### Gotcha found in this spike: closing the socket with zero application data races the Mac's `.ready` transition

First attempt at `ExporterHandshakeTest` closed the `SSLSocket` immediately after
`startHandshake()` returned, with no data ever written. Result: the *Android* side reported a
perfectly good handshake (protocol, ALPN, and `exportKeyingMaterial` all fine), but the *macOS*
listener never logged `EVENT type=ready` for those connections — instead:
```
LOG[listener] verify_block: peer_spki=dd647425534a178a... match=true elapsed_us=11296.0
EVENT type=failed role=server remote=127.0.0.1:60144 error="-9816: server closed session with no notification"
```
i.e. the verify_block ran and matched (the handshake *did* authenticate), but Network.framework's
own internal bookkeeping for "this connection is ready" had not yet completed when the TCP FIN
from Android's abrupt `socket.close()` arrived, and it surfaced as `.failed(-9816)` instead of
`.ready` followed by `.cancelled`. Fix (now in `ExporterHandshakeTest`): do one real `hello`/`ack`
application-data round trip before computing the exporter and closing, matching what every other
spike here already does (E03-01's own client always sends `hello` first). This is not a
correctness gap in the exporter or the pinning — both already happened — it is a reminder that
"handshake complete" and "safe to tear down the TCP connection with zero bytes exchanged" are not
the same event on Network.framework, consistent with E03-01's gotcha 5 (`.waiting` vs `.failed`
timing quirks). Worth carrying into E12-18/E01-01: don't build any production teardown path that
assumes an immediate, silent close after the handshake is "clean."

## §2 — Experiment 2: exporter-unavailable confirmation + in-band challenge fallback (API 29)

`scripts/run-e2e.sh teamorg_api29 challenge`. The macOS listener runs with `--challenge`: after
`.ready`, it sends 32 random bytes (`SecRandomCopyBytes`) over the already-authenticated TLS
session, reads back a length-prefixed ECDSA signature, and verifies it against the public key
captured from that connection's own `verify_block` (i.e. the same pinned key that just
authenticated the TLS handshake). `ChallengeHandshakeTest.exporterUnavailable_inBandChallengeSucceeds10x`
first asserts `exportKeyingMaterial` really is unavailable (`null`) on this device, then runs
`ChallengeClient.respond`: read the 32-byte challenge, sign it with
`Signature.getInstance("SHA256withECDSA")` over the same AndroidKeyStore key already used for the
TLS client certificate, write a 1-byte length + the DER signature, read back a 1-byte ack.

```
$ ./scripts/run-e2e.sh teamorg_api29 challenge
...
com.tandem.spike.e2ehandshake.ChallengeHandshakeTest:.
Time: 0.335
OK (1 test)
```
Android side (run 0):
```
run=0 handshake ok sdkInt=29 protocol=TLSv1.3 alpn=tandem/1
run=0 challenge_sha256=65a9fd2ddc4491b15c7ae2bce31e09679951f95b2b186d1135122d3921f99009 ackOk=true latencyMs=22
```
(`exportKeyingMaterial` unavailable is asserted, not merely logged: `assertNull(...)` — the test
fails outright if a future emulator/AOSP image on API 29 ever exposes it.) macOS side, same run:
```
EVENT type=ready role=server ... alpn=tandem/1 exporter_sha256=2a8404527279dc2810e8aad17fbeecad47fe0a3e10d79bcd4c8303c19015aeb5
EVENT type=challenge-verified role=server remote=127.0.0.1:61049 match=true challenge_sha256=65a9fd2ddc4491b15c7ae2bce31e09679951f95b2b186d1135122d3921f99009
```
All 10/10 runs: `match=true` on the macOS side, `ackOk=true` on the Android side, and the
`challenge_sha256` values line up pairwise (confirming the same 32 bytes were signed and verified,
not just "some" signature accepted). Note the asymmetry: the macOS side *can* and does still log
its own `exporter_sha256` on every run (Network.framework always has the exporter, per E03-01) —
it is only the Android/Conscrypt side below API 31 that lacks it, so there is nothing to compare
the Mac's exporter against on this device; this is expected, not a bug.

Latencies (ms, Android side, 10 runs, includes one 32-byte read + one ECDSA sign + one
length-prefixed write + one 1-byte ack read): `[10,10,10,11,11,11,12,12,12,22]`, p50=11, p95=12 —
i.e. the fallback's round trip costs roughly the same as, or less than, a full handshake on this
same hardware (§1's p50=19ms), and is nowhere near the backlog's 300ms/1000ms handshake budgets.

### Independent cross-check of the wire protocol (Swift-only, no Android)

Before running the emulator, the challenge/response wire protocol (32-byte challenge ->
length-prefixed DER signature -> 1-byte ack) was validated with a second, independent
implementation: `e2e-mac client-challenge` dials the listener using Security.framework
(`SecKeyCreateSignature`/`.ecdsaSignatureMessageX962SHA256`) instead of Conscrypt/AndroidKeyStore,
isolating "is the framing/verification logic right" from "does this specific Android API level
behave." Result: `ack_ok=true`, `challenge_sha256` matched between client and server logs. This
means the 10/10 API 29 result is not an artifact of one specific Conscrypt/AndroidKeyStore
quirk — the same protocol verifies correctly against a completely different TLS/crypto stack.

Raw logs: `spikes/e03-04-e2e/results/teamorg_api29-challenge/`.

## Security trade-off: RFC 9266 exporter vs. in-band challenge

**Exporter (RFC 9266, `TLS-Exporter("EXPORTER-Channel-Binding", "", 32)`):** derived locally and
identically by both peers from the TLS 1.3 key schedule (transcript hash + traffic secrets) that
this specific session negotiated. Nothing is transmitted to produce it — it is a *property of the
session's own key material*, not a message. Any difference in what the two peers believe they
negotiated (different session, different keys, different transcript) produces a different
exporter value by construction (§9 of `docs/spikes/nwlistener-mtls.md` shows this cross-checked
bit-exact against `openssl -keymatexport`; this spike shows it now bit-exact across platforms).
Binding a higher-layer proof to "this session" is then just "include (the SHA-256 of) the exporter
in the thing being signed" — one derivation, no round trip, reusable for multiple bindings within
the same session without any additional network interaction.

**In-band challenge (the recorded D-15 fallback):** the verifier sends 32 fresh random bytes over
the *already-established, mutually-authenticated* TLS session; the peer signs them with the exact
private key that TLS's own `CertificateVerify` already used to authenticate the handshake, and
returns the signature over the same session. This is not "as strong as the exporter" by an
identical mechanism, but it is bound to the same live session for four independent reasons that
each has to hold:

1. **Freshness.** The 32 bytes are freshly random per session (`SecRandomCopyBytes`), so a
   signature captured from a previous session cannot be replayed into a new one — the challenge
   itself never repeats.
2. **Confidentiality of the channel it travels in.** Both the challenge and the signature are
   TLS 1.3 application-data records, encrypted and integrity-protected under *this session's*
   negotiated keys. An attacker who is not a party to this specific session's key schedule cannot
   read the challenge or forge/modify the response record without breaking TLS 1.3's AEAD for that
   session — which is exactly the same assumption the exporter itself already depends on.
3. **The signing key is the same key that authenticated the handshake.** The signature proves
   "whoever is on the other end of *this* TLS connection controls the private key behind the
   pinned SPKI" — the same fact `CertificateVerify` already proved during the handshake, just
   re-demonstrated after the fact, over attacker-chosen-but-session-fresh bytes rather than the
   handshake transcript.
4. **Trust is anchored to the pin (invariant 3), not to the transport.** Both sides only reach the
   point of exchanging a challenge at all because `verify_block` (macOS) / `checkServerTrusted`
   (Android) already accepted the peer's SPKI against the expected fingerprint. The challenge
   exchange adds no new trust decision; it only demonstrates liveness/possession *given* that
   decision already stands.

**Replay-across-sessions:** equivalent for both mechanisms, but for different reasons. The
exporter can't be replayed because it is never transmitted and is recomputed from session-specific
key material every time. The in-band challenge can't be replayed because the 32 bytes are unique
per session — a signature over session A's challenge is not a valid signature over session B's
(different) challenge, so an attacker who recorded a full prior session gains nothing usable
against a new one.

**Relay/MITM given pinning:** an attacker sitting between two honest parties cannot complete
*either* side's mTLS handshake without possessing a private key matching the pinned SPKI (invariant
3; enforced by `verify_block`/`checkServerTrusted` in this spike, `constantTimeEqual`/
`constantTimeEquals`). If the attacker cannot get past that gate, neither the exporter (no session
exists to derive it from) nor the in-band challenge (no session exists to send it over) is ever
reached — both mechanisms are strictly *downstream* of the same trust decision, so in-band
challenge introduces no new relay/MITM surface beyond what pinned mTLS already has. The one
category of risk that is architecturally different (not created by this fallback, but worth
naming): the in-band challenge is an extra application-level exchange the peer must implement
correctly (length framing, signature algorithm agreement) — a bug there is a protocol bug, whereas
the exporter has no such surface because there is no message to parse. This spike's own listener
had exactly one such bug during development (the socket-close race in §1, not in the challenge
path itself), which is the practical argument for keeping the exporter as the default wherever it
is available and treating the challenge purely as an API-gap fallback (see recommendation below).

## Recommendation and reasoning

**Go with (b): exporter on API >= 31 (Android) and always on macOS; in-band challenge on Android
API 29/30.** This is what D-15 already specifies; this spike's job was to find a reason to
change that, and none was found:

- **(a) "exporter everywhere" was rejected.** It requires raising `minSdk` from 29 to 31, which
  drops Android 10 and 11 device support outright. That is a product/device-matrix decision (see
  `docs/testing/device-matrix.md`, and E03-03's own note that `teamorg_api29` is one of the
  matrix's explicit rows), not something a spike should force as a side effect of a crypto
  convenience. Nothing in this spike's results makes the exporter *necessary* — the fallback works
  and is cheap (§2) — so there is no technical justification to pay that product cost.
- **(c) "in-band challenge everywhere" was considered and set aside, not ruled out.** It is
  genuinely simpler: one code path instead of an `SDK_INT >= 31` branch in the pairing/rotation
  implementations (`E01-01`, `E01-02`, `E14-06`, `E14-07`, `E70-01`), and this spike shows it works
  correctly and fast (p50=11ms) even on the lowest-capability platform tested. It was not chosen as
  the primary recommendation because: (i) it discards a "free," textbook-strength primitive
  (RFC 9266) on every platform/API level that already has it (macOS always; Android API 31+, which
  will be an increasing share of the device matrix over the product's lifetime) in favor of a
  custom application-level protocol that has to be implemented, tested, and maintained correctly by
  this project; (ii) it adds one network round trip and one AndroidKeyStore signing operation to
  every session that needs a binding, on every device, forever, instead of only on the API 29/30
  minority; (iii) D-15 already recorded the hybrid shape as the intended design before this spike
  ran, and this spike found no defect in either half that would justify the rework and re-review
  cost of reversing that decision. If a future issue (e.g. `E14-06`/`E14-07` rotation) finds the
  two-code-path branching genuinely costly to maintain, (c) remains a reasonable simplification to
  revisit then — but that should be argued from the pairing/rotation implementation's own
  complexity, not from this spike, since here both paths were equally easy to get right.
- **(b) is confirmed go:** exporter values matched byte-for-byte 10/10 across platforms (§1), the
  fallback's unavailability precondition was confirmed (not just assumed) and its challenge/response
  correctly verified 10/10 on the actual low-capability platform it exists for (§2), and the
  security analysis above shows the fallback's guarantees are equivalent in the threat model that
  matters here (pinned mTLS, no MITM without the private key) — it is simply a different, slightly
  more expensive way of proving the same thing on a stack that cannot produce the RFC 9266 value.

## Cleanup

Every `run-e2e.sh` invocation's `trap cleanup EXIT` killed its listener process and the emulator
(`adb -s <serial> emu kill`) unconditionally, including the one run that hit the bash
empty-array/`set -u` bug before the fix (`Abort trap: 6` on the emulator, but still torn down, not
left running). Verified after the two experiment runs recorded in this document:
```
$ pgrep -fl "emulator|qemu-system|e2e-mac" || echo none running
none running
$ adb devices
List of devices attached
```
No physical device, login keychain, or real signing identity was used anywhere in this spike.

## Files

- `spikes/e03-04-e2e/mac/` — SwiftPM package `e2e-mac` (copied from `spikes/e03-01-nwlistener`,
  extended): `Sources/e2e-mac/Challenge.swift` (new: in-band challenge send/verify, the
  `PendingPeerKeyStore` single-slot handoff from `verify_block` to the ready handler, and the
  Swift-only `client-challenge` sanity double); `TLSSetup.swift` (added `onPeerVerified` hook);
  `Listener.swift` (added `challengeMode`/`runChallenge`); `main.swift` (added `--challenge`,
  `--client-name`, `--bind-host`, `client-challenge` subcommand). `Identity.swift`/`Pin.swift`/
  `Client.swift`/`Shell.swift` unchanged from E03-01.
- `spikes/e03-04-e2e/android/` — standalone Gradle project (copied from
  `spikes/e03-03-keystore-sslsocket`, renamed `com.tandem.spike.e2ehandshake`):
  `app/src/androidTest/.../GenerateIdentityTest.kt` (phase 1: generate + print pin),
  `ExporterHandshakeTest.kt` (experiment 1), `ChallengeHandshakeTest.kt` (experiment 2),
  `app/src/main/.../ChallengeClient.kt` (new: sign/respond helper).
  `KeystoreIdentity.kt`/`KeystoreKeyManager.kt`/`PinningTrustManager.kt`/`TlsHandshakeClient.kt`
  unchanged from E03-03.
- `spikes/e03-04-e2e/scripts/run-e2e.sh` — end-to-end driver for both experiments.
- `spikes/e03-04-e2e/results/teamorg_api34-exporter/`, `results/teamorg_api29-challenge/` — raw
  logs from the runs this document quotes.
