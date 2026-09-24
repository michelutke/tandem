# ADR-003: mTLS 1.3 self-signed + SPKI pinning vs. Noise protocol

- **Status:** Accepted
- **Date:** 2026-09-25
- **Issue:** E02-04

## Context

Every Tandem connection (control and media, ADR-005) needs a mutually
authenticated, encrypted transport between a phone that never has a stable
identity infrastructure to lean on and a Mac that is the sole listener
(ADR-002). Invariant 3 binds trust to SPKI fingerprints only, never IP or
device ID; invariant 6 requires constant-time secret comparison and
single-use, expiring pairing secrets; invariants 1 and 2 require every
socket to complete authentication before any application data flows, with
no fallback path. Two ways to build that channel were on the table: TLS 1.3
mutual auth with self-signed certificates, or a Noise protocol handshake
(Noise_XX) over raw TCP. The Phase 0 spikes (E03-01 macOS `NWListener`,
E03-03 Android `SSLSocket`/Conscrypt, E03-04 end-to-end handshake +
channel binding, E03-06 fallback-trigger catalogue) are the primary
empirical input to this decision, per D-48.

## Options

**(a) mTLS 1.3, self-signed P-256 certs, SPKI pinning — `Network.framework` (macOS) / platform `SSLSocket`+Conscrypt (Android)**
- Pros: first-class platform support on both sides — `Network.framework`'s
  `sec_protocol_options_set_verify_block` and Android's platform
  `X509TrustManager`/`X509ExtendedKeyManager` are audited, widely fielded
  TLS implementations, not hand-rolled or third-party crypto; certificate
  transport already carries the SPKI in a format both platform TLS stacks
  understand natively (X.509/SubjectPublicKeyInfo DER), so pin storage and
  comparison need no custom encoding; TLS 1.3's `CertificateVerify` gives
  mutual authentication, AEAD, and forward secrecy under the exact profile
  D-19 already specifies (no PSK/0-RTT, ALPN `tandem/1`, leaf-only P-256
  check); RFC 9266 channel binding is available for free via the TLS
  exporter on stacks that support it (D-15), confirmed bit-exact on macOS
  (E03-01 §9) and cross-platform on Android API 34 (E03-04 §1).
- Cons: TLS's own extensibility surface (session tickets, resumption,
  extensions) has to be explicitly locked down rather than simply absent,
  as a hand-verified profile (D-19) instead of a minimal Noise-style state
  machine; Android's `AndroidKeyStore` requires an undocumented key-spec
  workaround (`setDigests(DIGEST_SHA256, DIGEST_NONE)`) to make
  `CertificateVerify` signing work at all — omitting it fails every
  handshake with an opaque I/O error (E03-03 critical finding); the RFC
  9266 exporter is unavailable below Android API 31 (E03-03/E03-04),
  requiring a second mechanism for older devices.

**(b) Noise protocol (Noise_XX) over raw TCP**
- Pros: a minimal handshake state machine with no X.509/certificate
  baggage; natively derives a per-session symmetric key that can serve as
  a channel-binding input without any separate exporter API; a hand-rolled
  or single-purpose library has a smaller surface than a general-purpose
  TLS stack.
- Cons: neither platform gives Noise first-class support — `Network.framework`
  and Android `SSLSocket` only expose audited handshakes for TLS, so
  adopting Noise means either hand-rolling a handshake (a large
  security-critical surface with no platform audit trail) or taking on a
  third-party Noise library on both platforms, subject to the D-32
  supply-chain gate and ongoing maintenance; Noise's static keys would
  still need to be Keystore/Keychain-backed, and neither platform's Noise
  libraries integrate with hardware-backed keystores the way the native
  TLS stacks already do, so that glue would have to be built and
  independently reviewed; every property this project needs (mutual auth,
  AEAD, replay protection, channel binding) would have to be re-derived
  and re-validated by this project's own spikes and tests instead of
  inherited from a platform-maintained stack — exactly the empirical work
  E03-01/E03-03/E03-04 already did for option (a).

## Decision

Option (a): mTLS 1.3 with self-signed P-256 certificates and SPKI pinning,
`Network.framework` on macOS and platform Conscrypt `SSLSocket` +
`AndroidKeyStore` on Android. Noise is rejected for v1.

This is a GO per D-48's criteria: E03-01 passed every acceptance item for
`Network.framework` (one small, well-understood app-level gap, not a
stack-level blocker — see Consequences); E03-03 passed 10/10 TLS 1.3
client-cert handshakes on every available AVD, contingent on the
`DIGEST_NONE` key-spec fix; E03-04 proved the two platforms interoperate
end-to-end, 10/10 on both API 34 and API 29. No evidence from any spike
argues for Noise: option (a)'s cons above are implementation costs inside
an audited stack, not defects that Noise would avoid, since Noise would
reintroduce the same problems (hardware-backed key integration, per-OS
quirks) without a platform audit to lean on.

Channel binding is resolved by **D-67**: in-band challenge (32 fresh
random bytes signed over the already-authenticated TLS session, using the
same key that authenticated `CertificateVerify`) is used on every
platform and API level — superseding D-15's originally specified hybrid
(RFC 9266 exporter on Android API 31+ and macOS, in-band challenge only
below API 31). E03-04 proved both primitives correct and roughly
equivalent under this threat model given mutual SPKI pinning (§"Security
trade-off", `docs/spikes/channel-binding.md`); one code path on every
platform was chosen over the spike's own recommendation to halve the
implementation and test matrix (KISS). The exporter stays documented as
the stronger primitive to revisit if pinning assumptions ever change.

## Consequences

- Mac TLS identity is a Keychain-only P-256 key (PRD default), never
  Secure Enclave, in v1 — E03-02 recorded a NO-GO: `SecKeyCreateRandomKey`
  with a Secure Enclave token fails in every configuration reachable
  without a fully Xcode-provisioned, Apple-ID-signed app build.
- The Android `IdentityKeyStore` (E10-15) **must** generate its P-256 key
  with `setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)`;
  omitting `DIGEST_NONE` produces a key that signs `CertificateVerify`
  with the wrong JCA engine and fails every handshake with an opaque I/O
  error (E03-03).
- The Mac listener (`core/transport`, E01-01/E12-04) **must** add an
  explicit application-level ALPN check after `.ready`
  (`negotiatedALPN == "tandem/1"`, else cancel), because
  `Network.framework` enforces a *mismatched* ALPN offer but silently
  accepts a client that offers *no* ALPN extension at all (E03-01 §5).
- Channel binding uses the in-band challenge on every session, per D-67 —
  not gated on `Build.VERSION.SDK_INT`. `E01-01`, `E01-02`, `E14-06`,
  `E14-07`, `E70-01` implement one code path instead of D-15's two.
- No Secure Enclave key in v1 (see above); revisit only per E03-02's own
  note if a future spike with a signed-in Apple Developer account and
  Xcode-managed provisioning confirms SE access works from the real,
  properly-provisioned `Tandem.xcodeproj` app.
- `swift-nio-ssl` (E03-05) is not executed and not needed; the fallback
  triggers that would reopen it are catalogued in
  `docs/spikes/tls-stack-decision-criteria.md` (E03-06), not this ADR.

## Revisit criteria

This ADR has three independent, numeric revisit paths, all defined in
`docs/spikes/tls-stack-decision-criteria.md` (E03-06):

1. **Per-platform TLS-stack swap** (does not reopen (a) vs. (b), only the
   specific stack): reopen `swift-nio-ssl` for macOS if any of triggers
   M1–M4 fires in production code — e.g. M2: a session-resumption ticket
   or 0-RTT-eligible session issued on **≥ 1 of 20** connections despite
   tickets/resumption disabled; M3: a client offering no ALPN reaches a
   state where non-`VersionHello` bytes are processed on **≥ 1 of 10**
   connections. Reopen a bundled Conscrypt/BoringSSL stack for Android if
   any of A1–A4 fires — e.g. A2: a TEE-backed device's handshake p95
   exceeds **300 ms**, or a StrongBox-backed device exceeds **1000 ms**,
   over 10/10 and 20/20 runs (D-48), on any device in
   `docs/testing/device-matrix.md`.
2. **Reopening Noise** (this ADR's actual decision): only trigger X1 — the
   RFC 9266 exporter fails on **both** platforms in production **and**
   the in-band-challenge fallback (D-67) itself fails to bind
   `PairRequest`/`KeyRotation` to a specific TLS session under
   `mitm-lab` session-splicing scenarios (E15-10/E15-11). Per-platform
   stack swaps under (1) do not reopen this decision on their own.
3. **Physical-device gate (D-48):** this ADR's acceptance is unconditional
   only once every row in `docs/testing/device-matrix.md` passes 10/10 and
   20/20 mTLS handshakes at p95 **≤ 1000 ms** (StrongBox) / **≤ 300 ms**
   (TEE); today's evidence is emulator/software-key only (`SOFTWARE`
   security level on every AVD tried, p95 18–52 ms), which is why this
   gate is tracked as open follow-up rather than a blocker to Accepted
   status — a StrongBox device that fails only on latency may fall back
   to TEE-only rather than fail this ADR (D-48).

## Links

- Backlog: E02-04 (`docs/planning/backlog/phase-0.yaml`)
- Spikes: `docs/spikes/nwlistener-mtls.md` (E03-01), `docs/spikes/secure-enclave-identity.md`
  (E03-02), `docs/spikes/android-sslsocket-keystore.md` (E03-03),
  `docs/spikes/channel-binding.md` (E03-04), `docs/spikes/tls-stack-decision-criteria.md`
  (E03-06)
- PRD: `<architecture>` → Architecture decision records to write in Phase 0
  (ADR-003); `<risks>` — "Keystore-backed keys with `SSLSocket` client auth
  behave differently across OEMs", "Network.framework TLS client-cert and
  verify-block edge cases"
- Decisions: D-15 (channel binding, superseded for the fallback shape by
  D-67), D-19 (TLS profile), D-35 (E03-04 is the single session-binding
  outcome issue), D-48 (spike go thresholds), D-67 (in-band challenge
  everywhere)
- Invariants: 1 (mTLS-complete before app data), 2 (no plaintext/fallback
  listener), 3 (trust bound to SPKI only), 6 (constant-time, single-use,
  expiring secrets)
- Use cases / abuse cases: AC-01, AC-02
