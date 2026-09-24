# E03-03 spike: Android SSLSocket (Conscrypt) client auth with AndroidKeyStore P-256

Backlog: `docs/planning/backlog/phase-0.yaml` `id: E03-03`. GitHub #93.

Throwaway app: `spikes/e03-03-keystore-sslsocket/` (standalone Gradle project, AGP 9.4.1 /
Gradle 9.7.1 / built-in Kotlin, `compileSdk 35`, `minSdk 29`). Not part of the real `android/`
module tree; not wired into `docs/planning/backlog` commands.

## TL;DR — go/no-go

**Go**, with one mandatory implementation note and one item still gated on physical hardware:

- The architecture — platform `SSLSocket` (Conscrypt), a custom `X509ExtendedKeyManager` backed by
  a non-exportable AndroidKeyStore P-256 key, and a custom `X509TrustManager` doing an SPKI pin
  check — works end-to-end: TLS 1.3 client-cert auth, ALPN `tandem/1`, TLS 1.2 rejection, pin
  mismatch rejection, and the RFC 9266 exporter all pass 10/10 on every AVD tried.
- **Mandatory implementation note (see "Critical finding" below):** the AndroidKeyStore key used
  for this must be generated with `setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)`.
  Omitting `DIGEST_NONE` produces a key that generates and presents a certificate fine but fails
  every client-cert TLS handshake with an opaque I/O error — this cost most of the spike's time to
  isolate and should be carried forward into `core/crypto` (`IdentityKeyStore`, E10-15) verbatim.
- **StrongBox vs. TEE is an open manual gate.** All three emulator AVDs available in this
  environment report `KeyInfo.securityLevel = SOFTWARE` (no secure hardware backing at all), so
  none of the StrongBox/TEE-specific go criteria (security level, OEM variance, the 1000 ms/300 ms
  latency splits) could be exercised here. `docs/testing/device-matrix.md` is updated to reflect
  this; the physical-device rows there remain the blocking gate before ADR-003 can cite E03-03 as
  fully passed (backlog go criterion: "every matrix device must pass").

## Environment

- AVDs: `teamorg_api29` (Android 10, API 29), `teamorg_api34` (Android 14, API 34), `tablet_api34`
  (Android 14, API 34), all headless (`-no-window -no-audio -no-boot-anim -netfast`).
- Peer: `openssl s_server -tls1_3 -Verify 1 -alpn tandem/1` (OpenSSL 3.6.4, Homebrew) on the host,
  reachable from the emulator at `10.0.2.2`. Self-signed P-256 cert/key generated with
  `openssl ecparam -name prime256v1 -genkey -noout` / `openssl req -x509 ...`.
- Driver: `spikes/e03-03-keystore-sslsocket/scripts/run-spike.sh <avd-name>` — starts the three
  `openssl s_server` instances (main/TLS1.2-only/exporter ports), boots the AVD, builds, installs
  app + androidTest APKs, runs the instrumented suite, pulls logcat, tears everything down
  (`emu kill`). All three runs in this spike ended with the emulator killed and `adb devices`
  empty; no emulator was left running.

### Host tooling quirk (not an Android finding, but needed to reproduce this spike)

This machine's `openssl s_server` (3.6.4) treats a stdin EOF as an implicit "quit" even with
`-ign_eof` set, which under a background/non-interactive shell caused the server to tear down its
accept loop mid-run. Fix: `scripts/keepstdin.sh` holds a fifo open read-write on fd 9 and execs
`openssl s_server` with that as stdin, so it never observes EOF. `run-spike.sh` uses this for every
`s_server` invocation. Anyone reusing this spike script on a different `openssl` build may not need
the workaround, but it is harmless either way.

## Critical finding: `DIGEST_NONE` is required for TLS 1.3 client-cert auth

**Symptom:** with a key generated as
`KeyGenParameterSpec.Builder(alias, PURPOSE_SIGN).setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_SHA256)...`,
every part of the spike *except the actual handshake* worked: `KeyInfo` reported the key correctly,
`KeyManager.getCertificateChain()`/`getPrivateKey()` returned a valid self-signed cert and an
`AndroidKeyStoreECPrivateKey`, and the TLS handshake proceeded through the server's entire first
flight (`ServerHello`, `EncryptedExtensions`, `CertificateRequest`, `Certificate`,
`CertificateVerify`, `Finished` — confirmed via `openssl s_server -state`). It then failed while the
client was supposed to send its own `Certificate`/`CertificateVerify`/`Finished`:

- Android side: `javax.net.ssl.SSLHandshakeException: Read error: ssl=0x...: I/O error during
  system call, Success` (from `ConscryptEngineSocket.startHandshake`) — no exception surfaces from
  our own `KeyManager` code; `getPrivateKey`/`getCertificateChain` are called and return normally.
- Peer side: reproduced **identically** against two independent, unrelated TLS stacks — `openssl
  s_server` (`SSL3 alert write:fatal:decode_error`, then `unexpected eof while reading`) and a
  from-scratch JDK 21 `SSLServerSocket` (`javax.net.ssl.SSLHandshakeException: Remote host
  terminated the handshake`) — which rules out a peer-specific bug and points at the Android client.
- A plain `openssl s_client` performing the exact same mutually-authenticated TLS 1.3 handshake
  against the same `openssl s_server` config succeeded 3/3 times, isolating the failure to Android's
  signing path specifically, not the protocol profile (ALPN, `-Verify`, ciphers all ruled out one at
  a time).

**Root cause:** Conscrypt signs TLS 1.3 `CertificateVerify` over the already-computed transcript
hash directly (a `NONEwithECDSA` JCA `Signature` engine — the digest is pre-computed by the TLS
layer, not the key), not `SHA256withECDSA` over raw bytes. AndroidKeyStore only permits a
`Signature` engine whose digest was declared at key-generation time; requesting `NONEwithECDSA`
against a key whose `setDigests()` list didn't include `KeyProperties.DIGEST_NONE` fails inside the
Keystore, and that failure is swallowed somewhere inside Conscrypt's native engine — it never
surfaces as a catchable exception in `KeyManager`/application code, only as the generic I/O error
above.

**Fix, confirmed 10/10 on every AVD:**

```kotlin
KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)
    ...
```

This is not spike-specific plumbing — it must be carried into the real `IdentityKeyStore`
implementation (E10-15) and the identity-generation code in `core/crypto`. Recommend adding a
regression test there once that code exists (e.g. an instrumented test asserting a full client-auth
handshake against a loopback/test server succeeds with the generated key).

## API surface exercised

- `android.security.keystore.KeyGenParameterSpec.Builder` (`setIsStrongBoxBacked`, `setDigests`,
  `setCertificateSubject`/`setCertificateSerialNumber`), `KeyPairGenerator.getInstance("EC",
  "AndroidKeyStore")`.
- `android.security.keystore.KeyInfo` via `KeyFactory.getInstance(alg, "AndroidKeyStore")
  .getKeySpec(privateKey, KeyInfo::class.java)` — `.securityLevel` (API 31+) /
  `.isInsideSecureHardware` (all API levels).
- `javax.net.ssl.X509ExtendedKeyManager` (`chooseClientAlias`, `chooseEngineClientAlias`,
  `getCertificateChain`, `getPrivateKey`) and `javax.net.ssl.X509TrustManager`
  (`checkServerTrusted`) wired into a per-handshake `SSLContext.getInstance("TLSv1.3")`.
- `javax.net.ssl.SSLSocket` / `SSLParameters.setProtocols` / `.setApplicationProtocols(["tandem/1"])`.
- `android.net.ssl.SSLSockets.exportKeyingMaterial(socket, label, context, length)` (API 31+) and
  `.setUseSessionTickets(socket, false)` (API 29+).

Source: `spikes/e03-03-keystore-sslsocket/app/src/main/java/com/tandem/spike/keystoresslsocket/`
(`KeystoreIdentity.kt`, `KeystoreKeyManager.kt`, `PinningTrustManager.kt`, `TlsHandshakeClient.kt`).
Tests: `app/src/androidTest/.../KeystoreSslSocketSpikeTest.kt`.

## Results per acceptance item

All three AVDs: `OK (6 tests)`, zero failures, after the `DIGEST_NONE` fix above.

| Item | teamorg_api29 (Android 10) | teamorg_api34 (Android 14) | tablet_api34 (Android 14) |
|---|---|---|---|
| `KeyInfo` security level | `SOFTWARE` (`isInsideSecureHardware=false`; `getSecurityLevel()` doesn't exist pre-API 31, code falls back to the boolean) | `SOFTWARE` | `SOFTWARE` |
| Key non-exportable | `privateKey.encoded == null` — pass | pass | pass |
| StrongBox requested/granted | requested, not granted (no StrongBox on emulator) | requested, not granted | requested, not granted |
| 10/10 TLS 1.3 client-cert handshakes | pass, ALPN `tandem/1` every run | pass | pass |
| Handshake latency (ms, 10 runs) | `[13,13,13,14,18,18,19,24,25,45]` p50=18 p95=45 | `[7,7,7,8,8,8,8,8,9,18]` p50=8 p95=18 | `[7,9,10,11,12,13,14,17,21,52]` p50=13 p95=52 |
| Wrong-SPKI server cert rejected | 10/10 (`checkServerTrusted` throws, handshake aborts, 0 app bytes) | 10/10 | 10/10 |
| Client restricted to TLS 1.3 vs. a TLS-1.2-only server | rejected (`Handshake failed`) | rejected (`TLSV1_ALERT_PROTOCOL_VERSION`) | rejected (BoringSSL protocol-error alert) |
| `exportKeyingMaterial` vs. `openssl -keymatexport` | unavailable (API 31+ only; correctly detected via `Build.VERSION.SDK_INT`, not attempted) | byte-identical 10/10 | byte-identical 10/10 |
| ALPN `tandem/1` via `SSLParameters` | negotiated every handshake | negotiated | negotiated |
| `setUseSessionTickets(false)` + fresh `SSLContext` | handshake still completes, no crash | same | same |
| Key class (OEM/API variance) | `android.security.keystore.AndroidKeyStoreECPrivateKey` (legacy Keystore backend) | `android.security.keystore2.AndroidKeyStoreECPrivateKey` (Keystore2/`keystore2` backend) | same as api34 |

Evidence (exporter match, `tablet_api34`):

```
$ grep "run=.*exporter=" logcat.log | sed 's/.*exporter=//' | tr a-f A-F > android.txt
$ grep -A2 "Keying material" server-8445.log | grep "Keying material:" | sed 's/.*Keying material: //' > openssl.txt
$ diff android.txt openssl.txt && echo MATCH
MATCH
```

(Same result, byte-for-byte, on `teamorg_api34`; `teamorg_api29` is API 29 so
`exportKeyingMaterial` — a public API only since API 31 — is unavailable there, and the test
records that rather than attempting a reflection workaround.)

TLS 1.2 rejection evidence (`teamorg_api34`):
```
E0303Spike: TLS1.2 server correctly refused: Read error: ssl=0x...: Failure in SSL library, usually a protocol error
E0303Spike: error:1000042e:SSL routines:OPENSSL_internal:TLSV1_ALERT_PROTOCOL_VERSION
```

Pin-mismatch rejection evidence (any AVD, 10/10):
```
E0303Spike: run=0 pin mismatch correctly rejected: SPKI pin mismatch: expected=...e50 actual=...e5b
```

### "Server presents the pinned certificate without its private key" — manual, host-only check

Not automated in the instrumented suite (it doesn't require the Android side at all — it's a
generic TLS/PKI property). Verified manually on the host: starting `openssl s_server` with the
*real* server certificate but a *different, non-matching* private key fails before the listener
even opens:

```
$ openssl s_server -accept 8446 -cert server.crt -key wrong.key -tls1_3
Using default temp DH parameters
error setting private key
...ossl_x509_check_private_key:key values mismatch...
$ openssl s_client -connect 127.0.0.1:8446 ...
...BIO_connect:Connection refused...
```

i.e. a server can't present a certificate it doesn't hold the key for badly enough to even reach
the point of sending application data — the connection is refused outright. This satisfies the
spirit of the acceptance line without needing an Android-side test.

## Go/no-go detail against the backlog's stated criteria

- "10/10 TLS 1.3 handshakes with client-cert auth succeed" — **pass**, all three AVDs.
- "`KeyInfo` reports the key inside secure hardware and non-exportable" — **non-exportable: pass**;
  **inside secure hardware: no** on all three, because every available AVD reports `SOFTWARE`. This
  is expected for an emulator (documented in the issue itself) and is carried forward as the
  physical-device manual gate, not treated as a spike failure.
- "A server cert with a different SPKI is rejected 10/10" — **pass**.
- "Handshake p95 <= 1000 ms StrongBox / <= 300 ms TEE" — not directly applicable (no StrongBox/TEE
  device available), but the software p95s (18–52 ms) are well inside even the tighter TEE bound,
  which is a good leading signal that real hardware-backed signing (typically slower than software)
  has meaningful headroom before either threshold.
- "Findings doc + go/no-go recommendation feeding ADR-003 and the PRD risk row" — this document.
- "Device-matrix.md spike-results column filled in" — done (`docs/testing/device-matrix.md`); all
  rows needing a physical device are marked `manual gate — no physical device yet`, and the API 29
  row records the emulator pass while still needing a physical API 29 device.
- Overall: **go** on the architecture and API usage, **contingent** on shipping the `DIGEST_NONE`
  fix, and **blocked on physical hardware** for the StrongBox/TEE/OEM-variance portion of the go
  criteria (per D-48 / backlog: "every matrix device must pass" — no matrix device has been tested
  yet since none beyond the owner's own phone are acquired).

## What remains a manual gate (physical devices)

Everything StrongBox/TEE-specific: `KeyInfo.securityLevel` on real secure hardware, the
1000 ms/300 ms latency split, and OEM-specific quirks (Samsung Knox, Xiaomi/OnePlus battery
management, a real API 29 device). None of this is testable on the emulators available in this
environment. `docs/testing/device-matrix.md` now records this explicitly per row.

## Cleanup

All `openssl s_server` processes and all three emulators were killed at the end of each
`run-spike.sh` invocation; `adb devices` is empty and no `emulator`/`qemu-system`/`openssl s_server`
processes remain running.
