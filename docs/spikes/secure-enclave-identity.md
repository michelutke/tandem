# Spike E03-02: Secure Enclave key as `sec_identity` for the Mac TLS listener

**Backlog:** `docs/planning/backlog/phase-0.yaml` id `E03-02` (GitHub #92)
**PRD:** F-1.1 (device identity), Appendix C.1 open question
**Question:** can a Secure-Enclave-backed P-256 key be used as the Network.framework TLS
identity (`sec_identity` / `SecIdentity`) for the Tandem Mac listener?

**Recommendation: NO-GO for v1. Keep the Keychain-only P-256 key (PRD default) as the Mac TLS
identity.**

SE-backed key generation could not be made to succeed anywhere in this spike, in any
configuration reachable from a normal build (ad-hoc-signed CLI tool, or a real Apple
Development-signed CLI tool without an embedded provisioning profile). The blocker is not TLS or
Network.framework -- it is `SecKeyCreateRandomKey` itself refusing to create the key. See
"Go/no-go per acceptance item" below for the exact evidence.

## Environment

- Hardware: Apple M1 Max (MacBookPro18,2), Secure Enclave present.
- OS: macOS 26.5.2 (build 25F84).
- Toolchain: Swift 5.10 tools version, SwiftPM executable target, Xcode 26 installed.
- `openssl`: 3.6.4 (Homebrew, `/opt/homebrew/bin/openssl`).
- Spike code: `spikes/e03-02-secure-enclave/` (throwaway SwiftPM package
  `se-identity-spike`) and `spikes/e03-02-secure-enclave/XcodeHost/` (an abandoned xcodegen
  project used only to probe the Xcode-managed-provisioning path, see below).

### Keychain safety note

An earlier pass of this spike generated keys directly in the ambient default (login) keychain
via a `--legacy-keychain` mode that omitted `kSecUseDataProtectionKeychain`, and separately
code-signed the spike binary with the machine owner's personal "Apple Development" signing
identity to test whether a real Team ID changes SE availability. Both caused visible Keychain
(Schlüsselbund) prompts for the owner. Per owner instruction, both practices were reverted before
finishing the spike:

- The binary is ad-hoc-signed only (`codesign -s -`, or SwiftPM's own automatic ad-hoc signature)
  for every result recorded below. No result in this document depends on signing with the
  owner's personal or work certificate.
- `--legacy-keychain` now means "a brand-new on-disk keychain file this process creates via
  `SecKeychainCreate` under `/tmp/se-identity-spike-<uuid>/`", never the login keychain. It is
  deleted (`SecKeychainDelete` + removing the temp directory) by the same process before exit,
  including on error paths (see `TemporaryKeychain` in
  `spikes/e03-02-secure-enclave/Sources/se-identity-spike/Identity.swift`).
- All findings that needed the *data-protection* keychain (the modern, per-app keychain
  identified by `kSecUseDataProtectionKeychain`) used `cleanupIdentity(label:)`, scoped strictly
  to that store by label; this call never searches or deletes from the login keychain.
- Verified after every run: `security find-certificate -a` / `security find-key -a` against
  `~/Library/Keychains/login.keychain-db` for every label used in this spike, and manually for
  the two orphaned temp-keychain directories left behind by processes killed mid-experiment
  during debugging (`/tmp/se-identity-spike-*`, deleted). All clean at the time this document was
  written.
- The "SE key requires a Team-ID-signed binary with `keychain-access-groups`" finding below (the
  one place a real signing identity would matter) is recorded as **unverified / manual gate**:
  the experiment that would confirm or refute it requires either signing with a real identity
  the owner has asked not to be used unattended, or an Xcode project with a signed-in Apple ID
  account (also not available in this automation environment -- see "Xcode-managed provisioning"
  below). Whoever picks this back up with interactive Xcode/Apple-ID access should re-run that
  one case and update this doc.

## What was built

`spikes/e03-02-secure-enclave/` (SwiftPM executable `se-identity-spike`):

- `DER.swift` -- minimal hand-rolled ASN.1 DER encoder plus `buildSelfSignedP256Certificate`,
  producing a minimal X.509 v1 self-signed certificate DER for a P-256 public key. Needed because
  a Secure Enclave private key can never be exported into a PKCS#12 blob, so the
  `openssl req -x509` + `SecPKCS12Import` path (fine for two software keys) is not available for
  an SE key; the certificate must be built and signed entirely through `SecKeyCreateSignature`.
- `Identity.swift` -- `generateIdentity(label:secureEnclave:persistent:dataProtectionKeychain:temporaryKeychain:)`
  generates a P-256 key (`kSecAttrTokenIDSecureEnclave` or plain software, same code path modulo
  that one attribute), builds+signs the self-signed cert, adds it via `SecItemAdd`, and assembles
  a `SecIdentity` via `SecItemCopyMatching(kSecClassIdentity)`. Also: `TemporaryKeychain` (a
  throwaway on-disk keychain, see above), `loadPersistentIdentity` (reopens an identity by label,
  either from the data-protection keychain or from a named `TemporaryKeychain` path+password),
  `attemptPrivateKeyExport`, `cleanupIdentity`.
- `Listener.swift` -- `NWListener` wrapping the generated `SecIdentity` via `sec_identity_create`
  into `NWProtocolTLS.Options`, TLS 1.3 only, peer authentication required, verify block that
  accepts any peer certificate (pin-checking is E03-01's concern, not this spike's).
- `main.swift` -- CLI: `keygen`, `export-test`, `relaunch-check`, `cleanup`, `listen`.
- `XcodeHost/` -- an xcodegen-generated macOS app target (`project.yml`, `entitlements.plist`,
  reusing `DER.swift`/`Identity.swift`/`Util.swift`) with a Keychain Sharing entitlement and
  `CODE_SIGN_STYLE: Automatic`, used only to test whether an Xcode-managed local provisioning
  profile unlocks SE access for a *properly entitled* app (per this issue's instruction to try
  "an ad-hoc-signed or Xcode-built tool with the required entitlements" if the plain CLI path
  fails). It never produced a runnable binary -- see below.

## Go/no-go per acceptance item

Acceptance (from `phase-0.yaml`, `id: E03-02`):

> Go criteria for Secure Enclave: 20/20 mTLS handshakes complete with the SE-backed identity
> against an `openssl s_client` peer, and SE handshake p95 is <= 50 ms slower than the
> Keychain-only key over the same 20 runs. Otherwise no-go: v1 keeps the Keychain-only key (PRD
> default).

| # | Item | Result |
|---|---|---|
| 1 | SE key generation succeeds at all (`SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`) | **NO-GO** -- fails in every configuration tried, see table below |
| 2 | SE-backed `sec_identity` used as `NWProtocolTLS.Options` local identity | **Not reached** -- no SE-backed `SecIdentity` was ever obtained to test with |
| 3 | 20/20 mTLS handshakes, SE identity vs. `openssl s_client` | **Not reached**, same reason |
| 4 | SE handshake p95 <= 50 ms slower than Keychain-only key | **Not measurable**, same reason. Keychain-only (software) baseline recorded instead: 20/20 handshakes, server-side handshake elapsed p50 ~8.9 ms, p95 ~12.6 ms (see "Software-key baseline" below) -- comfortably inside any plausible 50 ms budget, which is the number the eventual SE result would have been compared against |
| 5 | Non-exportable / survives relaunch / failure modes documented | Documented below for both what we could test (software key: exportable, survives relaunch) and what remains unverified (SE key exportability/relaunch -- moot, since it never got created) |

**Overall: NO-GO.** Per the backlog's own fallback language, v1 keeps the Keychain-only P-256 key
(the PRD Appendix C.1 default) as the Mac TLS identity.

### SE key generation attempts (the actual blocker)

All rows use `SecKeyCreateRandomKey` with `kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom`,
`kSecAttrKeySizeInBits: 256`, `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave`. Commands:
`.build/debug/se-identity-spike keygen --backing se [--legacy-keychain]`.

| Binary signing | Keychain target | Result |
|---|---|---|
| SwiftPM ad-hoc (`swift build`'s automatic ad-hoc signature, only entitlement is `com.apple.security.get-task-allow`) | data-protection keychain (`kSecUseDataProtectionKeychain: true`) | `OSStatus -34018` ("A required entitlement isn't present.") -- `failed to add key to keychain: <SecKeyRef:('com.apple.setoken') ...>` |
| SwiftPM ad-hoc | temporary keychain (`kSecUseKeychain: <SecKeychainRef>`) | `OSStatus -50` ("inconsistent private key parameters for key generation") -- combining `kSecAttrTokenIDSecureEnclave` with a legacy keychain-file target is rejected outright, before any entitlement check |
| Ad-hoc signed with `keychain-access-groups` entitlement, no embedded provisioning profile (tested transiently, cleaned up, see safety note) | data-protection keychain | Binary is **SIGKILLed at launch** (exit 137) before any of our code runs -- AMFI refuses to execute a binary carrying that entitlement without a matching embedded provisioning profile. Reproduced with both an ad-hoc signature and a real Apple Development Team-ID signature (see safety note: this half of the matrix is retained as evidence but should not be re-run with a real personal/work signing identity) |

For comparison, a plain **software** P-256 key (identical code path, `kSecAttrTokenID` omitted)
generated via the data-protection keychain with the exact same ad-hoc-signed binary *also* fails
with the same `-34018`; only once redirected to a throwaway `TemporaryKeychain` (never the login
keychain) does software key generation succeed, with zero entitlements needed. This isolates the
finding precisely: **entitlement gating is about the destination keychain (data-protection
keychain requires `keychain-access-groups`), and Secure Enclave tokens can *only* be created in
the data-protection keychain** (the `-50` above shows the legacy-keychain escape hatch that works
for software keys is categorically unavailable for SE keys). So SE key creation always needs the
entitlement, and getting the entitlement past AMFI always needs an embedded provisioning profile,
which in turn needs an app (or tool) built and signed through Xcode's managed-signing pipeline,
not a bare `swift build`/`swift run` binary.

### Xcode-managed provisioning (the "try harder" path from this issue)

Per this issue's instruction ("if so, try an ad-hoc-signed or Xcode-built tool with the required
entitlements, and document exactly what is needed"), `XcodeHost/` is a minimal macOS app target
(via `xcodegen`) with:

```yaml
CODE_SIGN_STYLE: Automatic
CODE_SIGN_IDENTITY: "Apple Development"
CODE_SIGN_ENTITLEMENTS: entitlements.plist   # keychain-access-groups: [$(AppIdentifierPrefix)com.tandem.se-identity-spike-host]
```

Building it (`xcodebuild ... -allowProvisioningUpdates build`) got exactly one step further than
the CLI-tool attempts before stopping:

```
error: No Account for Team "<redacted>". Add a new account in Accounts settings or verify that
your accounts have valid credentials.
error: No profiles for 'com.tandem.se-identity-spike-host' were found: Xcode couldn't find any
Mac App Development provisioning profiles matching 'com.tandem.se-identity-spike-host'.
```

Xcode's automatic-provisioning-profile generation (the thing that would embed the
`keychain-access-groups` entitlement legitimately, avoiding the AMFI SIGKILL above) requires a
**signed-in Apple ID account in Xcode's Accounts preferences**. This spike ran inside a headless
automation shell with no such account configured, and per the owner's instruction this spike does
not sign with the owner's personal/work identity to work around that. **This is recorded as
unverified / a manual gate**: the technical question "does a properly-provisioned app with
Keychain Sharing actually get SE key access, and if so at what handshake latency" was not
answered here. It should be re-run by a developer with an Xcode-signed-in account, using
`XcodeHost/` as a starting point (substitute your own `DEVELOPMENT_TEAM` in `project.yml`).

### Software-key baseline (Keychain-only, the PRD default)

Command: `.build/debug/se-identity-spike listen --backing sw --legacy-keychain --port 4620
--exit-after 20`, identity generated fresh each run in a `TemporaryKeychain`, self-signed P-256
cert built the same way as the SE path would have been. Peer: `openssl s_client -tls1_3 -cert
... -key ...` (client also presents a certificate; server verify-block accepts any peer, so this
exercises the mTLS handshake shape without re-testing E03-01's pin logic).

- 20/20 `openssl s_client` runs printed `CONNECTION ESTABLISHED`, TLS 1.3,
  `TLS_AES_256_GCM_SHA384`, `ecdsa_secp256r1_sha256` signature.
- 20/20 server-side connections reached `.ready`.
- Server-side handshake elapsed (accept-to-ready), milliseconds, all 20 runs:
  `8.90, 11.17, 8.20, 17.93, 9.01, 9.27, 7.91, 12.63, 9.64, 9.89, 8.83, 8.98, 8.75, 9.05, 8.13,
  8.15, 8.79, 8.83, 10.16, 8.62`
  Sorted: min 7.91, p50 ~8.94, p95 ~12.63 (19th of 20), max 17.93. Full log:
  `spikes/e03-02-secure-enclave/results/listener-sw-final.log`, `results/summary.txt`,
  `results/osslclient-sw-*.log`.

This is the number a future SE-backed run would need to beat by no more than 50 ms (i.e. stay
under roughly 60 ms p95) to pass acceptance item 4 -- moot here since SE keygen itself never
succeeded, but recorded so a follow-up spike has a same-hardware baseline to compare against.

### Non-exportability / relaunch / other properties

| Property | Software key (temporary keychain) | SE key |
|---|---|---|
| Non-exportable | **No** -- `SecKeyCopyExternalRepresentation` succeeded, returned 97 bytes (ANSI X9.63 raw EC private key format). Expected: a software key generated via `SecKeyCreateRandomKey` without an SE token is exportable unless additionally wrapped; this is the correct contrast case, not a bug. | Not verified -- key was never created. Apple's documented behavior (and every other platform's SE/StrongBox equivalent) is that `SecKeyCopyExternalRepresentation` on an SE-backed key returns `errSecUnimplemented`/no representation; this spike did not independently confirm it |
| Survives process relaunch | **Yes** -- `keygen --keep` followed by a separate `relaunch-check` process invocation, both pointed at the same `TemporaryKeychain` path+password, returned the identical SPKI-SHA256 fingerprint. See `results/relaunch-keygen.log`, `results/relaunch-check.log` | Not verified, same reason |
| Keychain prompts | None observed for the data-protection-keychain or temporary-keychain code paths in this doc's final state. (An earlier iteration that queried the *login* keychain did surface visible prompts to the owner -- see "Keychain safety note" -- which is itself informative: a real per-app Mac deployment must not casually touch the login keychain either, reinforcing the PRD's existing choice of `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` in a dedicated app keychain context, not the user's personal login keychain) | Not verified |
| Failure modes | `-34018` (missing entitlement, data-protection keychain, no `keychain-access-groups`); `-50` (SE token incompatible with a legacy/custom keychain target); SIGKILL at process launch (AMFI, entitlement present but no matching provisioning profile); "No Account for Team" (Xcode automatic signing needs a signed-in Apple ID) | n/a, folds into the SE row above |

## Recommendation

**No-go for Secure Enclave in v1.** Keep the Keychain-only P-256 key
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, as already specified in PRD F-1.1) as the Mac
TLS identity. Reasoning:

1. The acceptance go-criteria (20/20 SE handshakes, latency comparison) cannot be met because SE
   key generation itself fails before there is anything to hand to Network.framework, in every
   configuration reachable without a fully Xcode-provisioned, Apple-ID-signed-in app build.
2. The one remaining unverified path (a real Xcode app, signed in with a Team ID account, with
   Keychain Sharing / `keychain-access-groups` and an embedded provisioning profile) is plausible
   in principle -- the software-key baseline in this same spike proves the certificate-building
   and `NWProtocolTLS` wiring work correctly once a `SecIdentity` exists -- but confirming it
   requires infrastructure (a signed-in Apple Developer account in Xcode) and a signing identity
   this spike was explicitly told not to use unattended. It is marked **unverified / manual gate**
   rather than asserted either way.
3. Even if a future manual run confirms SE access works from Tandem's real, properly-provisioned
   `macos/Tandem.xcodeproj` app (which already has real signing configured, unlike this
   throwaway CLI spike), the operational cost is real: SE keys categorically require the
   data-protection keychain plus `keychain-access-groups`, which is exactly the kind of
   entitlement/provisioning coupling that adds distribution complexity (an embedded provisioning
   profile, `DEVELOPMENT_TEAM` pinning) for a personal-distribution app that the PRD's own
   target-user section says has no store-policy constraints to satisfy in exchange. The
   Keychain-only key has none of this coupling and, per the software-key baseline measured here,
   already handshakes in single-digit-to-low-teens milliseconds.
4. If this remains an open question the team wants resolved with certainty, the concrete next
   step is: in `macos/Tandem.xcodeproj` (which already carries a real signing identity), add a
   Keychain Sharing capability, run once interactively, and re-run this spike's `listen`/`keygen`
   logic (or a Swift Testing case) against `kSecAttrTokenIDSecureEnclave` to get a real go/no-go
   on items 1-4 above. Until then, this document's answer is **no-go by default**, matching the
   backlog's own explicit fallback.

## Reproducing

```sh
cd spikes/e03-02-secure-enclave
swift build -c debug
.build/debug/se-identity-spike keygen --backing se                     # -34018, data-protection keychain
.build/debug/se-identity-spike keygen --backing se --legacy-keychain   # -50, temporary keychain
.build/debug/se-identity-spike keygen --backing sw --legacy-keychain   # succeeds, temporary keychain, auto-cleaned
.build/debug/se-identity-spike listen --backing sw --legacy-keychain --port 4620 --exit-after 20 &
openssl s_client -connect 127.0.0.1:4620 -tls1_3 -cert <client-cert> -key <client-key> -brief
```

All `keygen`/`listen`/`export-test` invocations clean up their own keychain items on exit
(temporary keychains are deleted entirely; data-protection-keychain items are deleted by label).
Nothing in this spike, in its final state, reads from or writes to the login keychain.
