# Tandem — threat model

STRIDE analysis of every network/protocol data flow in the architecture, per backlog issue
**E02-01**. This is chapter 1 of the threat model. Chapter 2 — Android IPC, Mac local surfaces,
storage, logs/crash reports, and CI/supply chain — is backlog issue **E02-08** (depends on this
issue) and will be appended below the marker at the end of this file.

Conventions used throughout:
- **Inv N** = security invariant N from `CLAUDE.md` / PRD `<architecture>`.
- **D-NN** = a row in [`decisions.md`](planning/decisions.md). D-60, D-61, and D-62 are cited
  ahead of that file: D-60 (phone answers at most one Heartbeat per second, extras dropped
  silently), D-61 (CONTROL-channel non-Heartbeat frames capped at 60/s per session,
  `LIMIT_EXCEEDED` beyond that), and D-62 (`Ring` is idempotent while already ringing; the alarm
  starts at most twice per rolling 10 s window) are recorded in `decisions.md`.
- **E##-##** = an owning backlog issue in `docs/planning/backlog/*.yaml` (implements the
  mitigation or the verifying test).
- **AC-##** = an abuse case in [`use-cases.md`](planning/use-cases.md).
- Mitigations that do not yet have a dedicated `security:`/`mitm-lab`/`pcap-audit` tdd entry cite
  the owning issue's `unit:`/`integration:`/`conformance:` tests instead and are flagged as such.

`docs/protocol/SPEC.md` (E01) had not been written when this chapter was drafted (Phase 0 is
still in flight); message and field detail below is sourced from `docs/PRD.md`, `decisions.md`
D-rows, and the backlog issue descriptions that will become SPEC sections. Re-check this
document against SPEC.md once E01 lands (see Assumptions, §6).

---

## 1. Scope and method

One STRIDE pass (Spoofing, Tampering, Repudiation, Information disclosure, Denial of service,
Elevation of privilege) per arrow in the PRD `<architecture>` data-flow diagram, plus the
on-device sources that feed the multiplexed control connection. Per E02-01's scope split (D-33),
this chapter covers **network and protocol flows only**: the mTLS control and media connections,
every channel they carry, pairing, discovery, key rotation, revoke, and the boundary where an
on-device data source (NotificationListener, clipboard, MediaStore/SAF, SMS provider, Contacts,
Telecom, MediaProjection, AccessibilityService) hands data to the mux. It does **not** cover:
Android IPC internals (exported components, PendingIntents beyond the wire-triggered fire,
tapjacking), Mac local surfaces (loopback, share-extension queue, Finder Services, pasteboard
markers), on-disk storage, logs/crash-report pipelines in depth, or CI/supply chain — those are
chapter 2, E02-08.

## 2. System overview and trust boundaries

Actors: **Owner** (single user, both devices), **Phone** (Android, TLS client only), **Mac**
(macOS, sole TLS listener), **Attacker** (anyone else on the local network, or with brief
physical access to a screen showing a QR code).

Trust boundaries crossed by the flows below:

| # | Boundary | Notes |
|---|---|---|
| B1 | Phone app sandbox ↔ AndroidKeyStore (StrongBox/TEE) | Private key never leaves hardware; only signatures/handshake operations cross. |
| B2 | Mac app sandbox ↔ Keychain / Secure Enclave | Same shape as B1. |
| B3 | Phone/Mac process ↔ local network (Wi-Fi) | Untrusted: attacker may be on the same L2/L3 segment (AC-01, AC-02, AC-04, AC-13). |
| B4 | Pairing window (temporary trust relaxation) | The Mac listener accepts an unpinned client certificate *only* while a pairing window is open (F-2.1); this is the one deliberate, time- and attempt-bounded hole in Inv 3/5. |
| B5 | Optical channel (QR code) | One-way, out-of-band; carries the Mac's fingerprint and a single-use secret, not a key exchange in itself. |
| B6 | Authenticated session ↔ application channels | Once mTLS completes, all nine channels (F-3.2) and the media connection share the same peer identity; per-channel caps (D-21, D-26, D-27) are the only remaining boundary between channels. |
| B7 | OS-granted data source ↔ mux | NotificationListener, clipboard, MediaStore/SAF, SMS provider, Contacts, Telecom, MediaProjection, AccessibilityService each cross from an OS permission surface into an Envelope destined for the wire; the OS-permission side of this boundary is E02-08. |

## 3. Data-flow diagram

```mermaid
flowchart LR
  subgraph Phone["Android phone — TLS client only, no listeners (Inv 4)"]
    direction TB
    NL[NotificationListenerService]
    CBSRC["Clipboard entry points
share / QS tile / PROCESS_TEXT / foreground"]
    FSRC["MediaStore / SAF
files + photos"]
    SMSSRC[Telephony provider]
    CTSRC[ContactsContract]
    TCSRC[TelecomManager]
    MPSRC[MediaProjection + MediaCodec]
    ASSRC[AccessibilityService]
    MUXA[["Mux: CONTROL · NOTIFY · CLIPBOARD · FILES · SMS · CONTACTS · CALLS · INPUT · STATUS"]]
    IDA[("AndroidKeyStore
P-256 identity")]
  end

  subgraph Mac["macOS — single mTLS listener (Inv 2)"]
    direction TB
    IDM[("Keychain
P-256 identity")]
    MUXM[["Mux"]]
    UN[UNUserNotificationCenter]
    PB[NSPasteboard]
    FDST["Downloads/Tandem
+ photo cache"]
    MSGUI["Messages / Contacts
/ Calls UI"]
    VT[VideoToolbox mirror window]
    INJUI["Mouse/keyboard
capture"]
    BONJOUR[["Bonjour
_tandem._tcp advertise"]]
  end

  QR{{"QR pairing
optical channel, B5"}}

  NL --> MUXA
  CBSRC --> MUXA
  FSRC --> MUXA
  SMSSRC --> MUXA
  CTSRC --> MUXA
  TCSRC --> MUXA
  ASSRC <-.-> MUXA

  IDA == "control mTLS (phone dials)" ==> IDM
  MUXA <== "control mTLS, 9 channels" ==> MUXM
  MPSRC == "media mTLS (ticket-bound)" ==> VT
  INJUI -. "INPUT frames on control mTLS" .-> ASSRC

  MUXM --> UN
  MUXM --> PB
  MUXM --> FDST
  MUXM --> MSGUI

  BONJOUR -. "discovery hint only, never a trust decision" .-> Phone
  IDM == "Mac renders QR, pairing window 120s, 3 attempts" ==> QR
  QR == "phone scans, dials, pins Mac fp; owner confirms 6-digit code" ==> IDA
```

## 4. Threat model per flow

### 4.1 Control connection establishment (mTLS handshake + admission control)

Assets: long-term identity keys (B1/B2), the pinned trust store, the application-data boundary
(Inv 1).

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing | Attacker presents an unpinned or swapped certificate as the Mac or the phone. | SPKI pin check in the verify callback / `X509TrustManager`, constant-time compare (Inv 1, 3, 5, 6; E12-02, E12-05, E10-10). | None once paired; the only intentional exception is the pairing window (§4.3). | `security: mitmLab_unknownClientCertOutsidePairingWindow_zeroAppBytesDelivered`, `mitmLab_wrongServerCertFingerprint_zeroAppBytesDelivered`, `mitmLab_swappedCertsBetweenPairedDevices_zeroAppBytesDelivered` | AC-01 |
| Spoofing | A host that reused a previously-trusted IP address answers with a different key. | Trust bound to SPKI only, never IP/hostname/deviceId (Inv 3); pin check re-runs on every reconnect (E12-05, E21-06). | None. | `mitmLab_phoneRevokedWhileOffline_zeroAppBytesDelivered`; UC-04 acceptance ("wrong peer on a reused IP never receives application data") | AC-01, AC-04 |
| Tampering | Downgrade to TLS 1.2, force session resumption, or offer 0-RTT/early data to weaken or replay the handshake. | TLS 1.3-only both sides (Inv 1; E12-01, E12-04), resumption/0-RTT explicitly disabled (E12-03), ALPN `tandem/1` required, no PSK offered, no post-handshake authentication (D-19). | None. | `security: mitmLab_tls12OnlyClientHello_protocolVersionAlert`, `mitmLab_fullHandshake_zeroSessionTicketsIssued`, `mitmLab_resumptionAttempt_neverResumed`, `mitmLab_zeroRttEarlyData_zeroEarlyBytesDelivered`, `mitmLab_androidClientAfterTicketIssued_nextHelloOffersNoPsk`, `mitmLab_clientWithoutTandemAlpn_handshakeFails`, `opensslSClientTls12_againstMacListener_handshakeFails` | AC-04 |
| Tampering | Peer presents the pinned certificate but signs `CertificateVerify` with a different key (key-less impersonation). | `CertificateVerify` is always enforced by the native TLS stack, independent of the pin check (D-19); spike-verified on both platforms (E03-01, E03-03). | None; depends on the platform TLS stack's own correctness (see Assumptions). | `mitmLab_pairedPhoneCertWithoutPrivateKey_handshakeFails`, `mitmLab_macCertWithoutPrivateKey_phoneHandshakeFails` | AC-01 |
| Tampering (non-standard leaf key) | Peer presents a certificate whose leaf public key is not the expected 91-byte uncompressed P-256 SPKI (e.g. RSA, a different curve, or a compressed point), probing for a parser-confusion or weaker-curve acceptance path. | Leaf key type/format is checked and rejected *before* the pin compare even runs, on both sides (D-19; E12-02, E12-05). | None. | `peerAuthorizer_nonP256LeafKey_rejected` (E12-02), `trustManager_nonP256LeafKey_rejectedBeforePinCompare` (E12-05) | AC-01 |
| Repudiation | No signed record of which peer connected when. | `lastSeen` and negotiated capabilities recorded in the trust store on every `Ready` transition (E12-14, E12-17). | No cryptographic non-repudiation beyond `lastSeen`; accepted for a single-owner app (see Assumptions). Also note: 1 control session per peer SPKI, a newer `Ready` session replaces the older one (E01-22) — see the cloned-key residual in §5. | `unit:`/`integration:` coverage under E12-14/E12-17 | — |
| Information disclosure | Passive eavesdropper reads handshake or application data. | TLS 1.3 AEAD suites only, mutual auth, channel-binding-bound proofs prevent a relayed-credential MITM (Inv 1; D-15, D-19); no SNI sent, avoiding a cleartext hostname leak (D-19). | None for cert/application-data content; ALPN value and port remain visible in cleartext — see the traffic-analysis residual row below. | `security: pcapAudit_jvmHarnessPairAndReconnect_zeroNonTls13Records`, `canaryProcedure_jvmHarnessPairingWithCanaryName_zeroOccurrencesInCapture` | AC-02 |
| Information disclosure (traffic analysis) | A passive on-path observer cannot read certificates or application data (TLS 1.3), but can still: fingerprint the app via the cleartext ClientHello's ALPN value (`tandem/1`) and the fixed listening port; correlate record lengths/timing to guess which feature is active (e.g. a large steady stream suggests mirroring); and see, via mDNS browse/advertise traffic, that a Tandem user is present on the network at all (§4.16). | TLS 1.3 encrypts the certificate messages and all application data (Inv 1); ALPN and port are visible on the wire in any TLS deployment and are not treated as secrets. | Accepted residual: app *identity* (not content) is observable to a local passive observer via ALPN/port/mDNS service type and via traffic shape. No code-level fix removes this without protocol-level padding/cover traffic, out of scope for v1. | Covered indirectly by the pcap-audit "only TLS 1.3 records, no canary" tests above; no dedicated traffic-analysis test exists. | AC-02 |
| Denial of service | Connection floods, slowloris, or stalled handshakes/hellos before authentication exhaust the single listener or burn pairing attempts. | Pre-auth admission control: TLS 10 s deadline, `VersionHello` 5 s deadline enforced independently on each side (E12-07 Mac, E12-15 Android), ≤ 8 pre-auth connections, ≤ 2 per IP, a source IP with ≥ 10 failed handshakes within 60 s is refused for 60 s (throttle never used as a trust input) (D-20; E01-22, E12-18). | A well-resourced attacker can still consume the 8-connection pre-auth budget from several IPs simultaneously; paired peers still connect per the acceptance bar, but a new pairing attempt during a large-scale flood may be delayed. | `security: mitmLabDos_stalledTcpNoClientHello_closedWithin11s`, `mitmLabDos_tlsDoneNoVersionHello_closedProtocolTimeoutWithin6s`, `mitmLabDos_connectionFloodFromOneSource_pairedPeerStillReady`, `mitmLabDos_failedHandshakeBurst_sourceThrottledOtherSourceReady`, `hello_noPeerHelloWithin5s_closesProtocolTimeout` (E12-07/E12-15) | AC-13 |
| Elevation of privilege | Peer claims a newer/incompatible protocol version or capability set to unlock a code path the receiver doesn't expect. | Explicit `VersionHello` capability negotiation on the CONTROL channel; a version mismatch fails closed with a visible error (Inv 5; E12-07, E12-15). | None. | `security: mitmLab_helloUnsupportedMajorVersion_closedWithVersionMismatch`, `mitmLab_helloUnsupportedMajorVersion_menuShowsVersionError` | AC-04 |

### 4.2 Framing and envelope decoding (shared by every channel)

Assets: the multiplexer's parser state; applies identically to every channel in §4.4–4.14.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Tampering | An authenticated-but-malicious peer sends a malformed frame (bad length prefix, invalid protobuf, out-of-range channel id, oversized payload) to crash the parser or corrupt memory. | Max frame 1 MiB (F-3.2); a single `MALFORMED_FRAME` close code with no oracle for the specific defect (D-13; E01-05, E01-19, E11-02, E11-04); frame and envelope decoders are fuzzed 24 h per target before release with zero crashes/hangs required (D-47; E71-01, E71-02, E71-04, E71-13). | Fuzzing bounds known input classes over a finite campaign; a zero-day parser bug outside the 24 h corpus is possible until found (accepted residual of any fuzz-based program). | `security: frameParserFuzz24h_jazzerCampaign_zeroCrashesOrHangs`, `frameParserFuzz24h_libFuzzerCampaign_zeroCrashesOrHangs`, `envelopeDecoderFuzz24h_jazzerCampaign_zeroCrashesOrHangs`, `envelopeDecoderFuzz24h_libFuzzerCampaign_zeroCrashesOrHangs`, `domainDecoderFuzz24h_everyJazzerTarget_zeroCrashesOrHangs`, `domainDecoderFuzz24h_everyLibFuzzerTarget_zeroCrashesOrHangs` | AC-07 |
| Denial of service | A single *feature* channel's frame flood starves other feature channels (e.g. a FILES transfer delaying NOTIFY). | Credit-based per-channel flow control (F-3.2; E11-07, E11-08, E11-13, E11-14) bounds the eight feature channels against each other; starvation regression tests. **CONTROL is exempt from this credit accounting** — control/heartbeat traffic must never be backpressured, so it needs its own cap instead (see the next row). | None observed within tested caps for the feature channels. | `E11-09`/`E11-10` starvation regression tests | AC-19 |
| Denial of service | An already-authenticated peer floods the CONTROL channel itself (Heartbeats or other control frames) to drain phone battery via repeated wake/reply work, or to degrade the session — this is not caught by the feature-channel credit system above because CONTROL is exempt from it. | Heartbeat replies capped at one per second, extra Heartbeats dropped silently — no reply, no error, no close (D-60; E20-15); non-Heartbeat CONTROL frames capped at 60/s per session, the 61st in a rolling 1 s window closes the connection `LIMIT_EXCEEDED` (D-61; E20-05). | Bounded, not eliminated — an authenticated peer can still sustain a flood up to the cap, consuming some battery/CPU at that rate. | `security: mitmLabDos_authenticatedHeartbeatFlood1000PerSecond_phoneRepliesCappedSessionStaysUp` (E20-20) | AC-19 |
| Elevation of privilege | A debug/echo/canary-injection/test-only message type is accepted over the wire in a release build. | No such message type exists in the schema at all — debug and release builds speak an identical protocol (D-02); an unknown payload type closes the connection; release artifacts are scanned for test-only code (D-30; E00-30). | None if the schema and release scan stay in sync; a future protocol change that reintroduces a debug path would need to also update the scan's fixture list. | Proto schema review (E01-04, E01-10), `ci:` release scan under E00-30, `security: pcapAudit_fullFeatureCanarySession_onlyTls13RecordsOnTandemPort`, `logAudit_fullFeatureCanarySession_zeroCanaryOccurrences` | AC-11 |

### 4.3 QR pairing (optical channel, pairing window, PairRequest/PairAccepted/PairRejected, confirmation code)

Assets: the 128-bit pairing secret, the bootstrap of first trust between the two identity keys.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing ("evil QR") | Owner is tricked into scanning an attacker's QR so the phone pairs with the attacker's Mac. | Mac shows the phone name and a 6-digit confirmation code; phone shows the same code and commits trust only after the owner taps "Codes match" (D-16, D-41; E14-08, E14-11, UC-03). The code itself is derived from *this specific TLS session's* channel-binding value, not just the shared secret (computed by a shared helper fed `channelBinding` + sanitized name: E14-05, E01-18, E10-12/E10-13). Because channel binding is per-session, a relay attack (attacker forwards bytes between the real phone and the real Mac but terminates TLS itself, i.e. two distinct TLS sessions) produces two *different* channel-binding values and therefore two different codes on the two screens — this is exactly why a relayed pairing is supposed to show mismatched codes, giving the owner a detectable signal. | Owner could still mis-compare the code under distraction/duress, or simply not check it (see the captured-QR row below); accepted per owner decision D-41 (keep the tap even though it adds a human step to the pairing-latency target). | `unit:`/`integration:` evil-QR tests under E14-08/E14-16; `e2eHarness_pairing_macDialogCodeEqualsClientCode` (E14-16) proves the Mac dialog code equals the client's own computed code for a genuine (non-relayed) session. | AC-20 |
| Spoofing (attacker holds the captured secret) | An attacker who saw/photographed the QR (see the Information disclosure row below) holds the same secret and Mac fingerprint the owner's phone does. The attacker can run their *own* device through the entire pairing flow as if it were the phone: dial the Mac, compute a correct proof (they have the secret), and — because the confirmation code is a function of the secret-derived proof material and their own session's channel binding — see a code that the Mac will also show, then tap "confirmed" on their own device. | The real defense is not the secret (the attacker also has it); it is (a) the Mac-side dialog, whose default button and Escape both map to Don't Pair — the owner must explicitly click Pair after checking the code and device name (D-16; E14-08, `pairConfirmation_defaultAndEscapeAction_isDontPair`), and (b) only one candidate connection is processed at a time (D-18; E12-02, `peerAuthorizer_secondUnknownCertWhileCandidateInFlight_rejected`) — an attacker's session and the owner's own phone's session cannot both be mid-pairing simultaneously, so the owner is shown one device name at a time and can notice it isn't theirs. | Owner clicks "Pair" without actually checking that the shown device name/code is their own phone — the default-deny UI reduces but does not eliminate a careless click. Also: the Mac commits the peer's fingerprint to the trust store on its own "Accept" click (E14-08), which happens *before* the phone side's separate owner confirmation step (E14-05 commits only after "Codes match" is tapped there) — if the attacker's device is the one accepted, or if the real owner accepts on the Mac but then never completes the phone-side tap, the Mac is left with a trust record whose peer never confirmed; it is visible with a last-seen time and revocable (E14-14), but it is a dangling record until then. | `pairConfirmation_defaultAndEscapeAction_isDontPair` (E14-08); `peerAuthorizer_secondUnknownCertWhileCandidateInFlight_rejected` (E12-02) | AC-17 (partial), AC-20 |
| Denial of service (candidate-slot race) | An attacker who captured the QR races the owner's own phone to occupy the single in-flight pairing-candidate slot (D-18). Whoever connects first with a valid proof occupies the slot until the window/attempt resolves, locking out the legitimate phone's simultaneous attempt for that time. | Only one pairing candidate is processed at a time by design (D-18; E12-02, `peerAuthorizer_secondUnknownCertWhileCandidateInFlight_rejected`); the owner sees whichever device actually reached the dialog and can decline it and retry. | An attacker in range who is faster than the owner's phone can repeatedly win the race and force the owner to retry, though never gains trust without also winning the Mac-side confirmation (see the row above). Annoyance/lockout-for-the-window, not a trust bypass. | `peerAuthorizer_secondUnknownCertWhileCandidateInFlight_rejected` (E12-02); `security: mitmLab_secondConcurrentPairingCandidate_rejectedInHandshake` | AC-13, AC-20 |
| Spoofing (replay across sessions) | A captured `PairRequest` is replayed on a new or a different TLS session. | Proof is bound to the specific TLS session via the RFC 9266 exporter channel binding `cb` (D-14, D-15; E01-02, E01-18, E14-06, E14-07). | None if the exporter spike (E03-04) is a go; if it is a no-go, the in-band-challenge fallback (D-15) must be re-verified before this row is trusted. | `security: mitmLab_replayedPairRequestAfterCompletion_noPairAccepted`, `mitmLab_pairRequestReplayedOnNewTlsSession_noPairAccepted` | AC-03 |
| Spoofing (brute force / stale secret / wrong-key proof) | Attacker guesses the secret, uses an expired secret, or presents a proof computed for a different phone key. | 120 s expiry, 3-attempt burn limit, constant-time HMAC compare (Inv 6; E14-05, E14-07, E14-09). | None within the 3-attempt/120 s budget; a new QR resets the budget visibly to the owner. | `security: mitmLab_pairRequestAfterSecretExpiry_noPairAccepted`, `mitmLab_fourthAttemptAfterThreeFailures_rejected`, `mitmLab_correctProofAfterWindowExhausted_rejected`, `mitmLab_proofForDifferentPhoneKey_noPairAccepted` | AC-03 |
| Tampering (rejection oracle) | Wire-visible `PairRejected` reason lets an attacker distinguish "bad proof" from "expired" from "exhausted" to refine an attack. | `PairRejected` carries only `REJECTED_BY_OWNER` or `PAIRING_UNAVAILABLE` on the wire; the detailed reason stays local (D-17; E01-02, E01-11, E14-09, E15-09). | Accepted residual (timing side-channel): the *reason* is collapsed to two codes, but the *time* to reject may still differ between an early rejection (e.g. no window open) and a full constant-time proof comparison before rejecting (Inv 6; E10-10 only equalizes timing *within* the proof-compare path, not *across* the different rejection paths). A sufficiently patient network attacker could infer which path was taken from response latency even though the wire reason never says so. No dedicated timing-equalization mitigation exists across paths yet. | `security: mitmLab_badProofRejection_wireReasonPairingUnavailableOnly` proves the wire-visible reason is collapsed; no test measures cross-path response-timing uniformity. | AC-03 |
| Tampering (concurrent candidates / mid-pairing Revoke) | A second pairing candidate opens while one is in flight, or a `Revoke` is injected on the pairing connection itself. | One in-flight candidate only (D-18; E14-02); `Revoke` is accepted only on an already-trusted `Ready` session, never a pairing candidate (D-23; E01-11). | None. | `security: mitmLab_secondConcurrentPairingCandidate_rejectedInHandshake`, `mitmLab_revokeOnPairingCandidateConnection_trustStoreUnchanged` | AC-03 |
| Tampering (malformed QR payload) | Malformed or oversized QR content (hostnames instead of literal IPs, > 8 addresses, oversized name, multicast/unspecified address) fed to the parser. | Grammar hardening: `a` restricted to 1–8 literal IPv4/IPv6 addresses, no hostnames, no unspecified/multicast/broadcast; `n` ≤ 64 UTF-8 bytes; every violation a MUST-reject with a specific vector-tested error (D-18; E01-02, E01-21). | None within the vectored fixture set; new malformed shapes need a new vector before they're provably rejected. | `unit: qrPayloadVector_hostnameInAddressList_expectedErrorInvalidAddress` and the E01-21 vector suite | AC-03, AC-07 |
| Information disclosure | The QR image itself is visible to anyone who can see the Mac's screen during the pairing window (physical access during the pairing window). | Network/protocol layer alone cannot prevent optical capture; see the "attacker holds the captured secret" and candidate-slot-race rows above for what happens next and why it still fails closed on trust. | Full local-attacker analysis (screen-capture exclusion, loopback, physical access) is E02-08 (AC-17); recorded here as a residual because the QR *is* this flow's channel (see §5, item 2). | Partial: covered by the same evil-QR/captured-secret tests above. | AC-17 (partial), AC-20 |
| Denial of service | Attacker repeatedly opens/idles pairing candidates to exhaust the 3-attempt budget or hold the pre-auth slot open. | A pairing-candidate connection that sends no `PairRequest` within 10 s of the hellos is closed and burns one attempt (D-18/D-20; E14-02, `pairingWindow_candidateSilentFor10s_closedAndOneAttemptBurned`); the same pre-auth caps and deadlines apply generally (E01-22, E12-18); regenerating the QR resets the budget visibly (E14-11). | An attacker within Wi-Fi range can force the owner to regenerate the QR repeatedly; annoyance-level DoS, not a trust bypass. | `security: mitmLabDos_threeIdlePairingCandidates_windowExhaustedNoPairAccepted`; `pairingWindow_candidateSilentFor10s_closedAndOneAttemptBurned` (E14-02) | AC-13 |
| Elevation of privilege | Pairing-only messages (`PairRequest`, etc.) sent outside an open pairing window, or by an already-authenticated peer trying to re-invoke pairing. | Pairing state machine only accepts the pairing message set while its window is open (E14-02, E14-05); an authenticated session has no path back into pairing. | None. | Covered by the mitm-lab pairing suite above. | AC-03 |

### 4.4 CONTROL channel (heartbeat, capability negotiation, media ticket issuance)

Assets: liveness signal, negotiated capability set, media ticket material in transit.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Tampering / Spoofing of Heartbeat | An on-path party forges or suppresses heartbeats to fake liveness or force a false dead-peer verdict. | Runs entirely inside the already-authenticated mTLS session, so requires breaking transport confidentiality/integrity first (covered in §4.1); the Mac drives liveness (sends after 15 s idle, dead at 45 s), phone answers within 1 s using elapsed-realtime so Doze drift can't be exploited to fake a timeout (D-10; E20-05, E20-15). | None beyond the transport's own guarantees. | `unit:`/`instrumented:` coverage under E20-05, E20-15, E20-12. | AC-01 (via transport) |
| Denial of service (Heartbeat flood / battery drain) | An already-authenticated peer sends Heartbeats far faster than the 15 s/45 s liveness contract expects, to force wasted reply work and drain phone battery. | Phone answers at most one Heartbeat per second; faster Heartbeats are dropped silently (D-60; E20-15, `heartbeatResponder_hundredHeartbeatsIn1s_atMostOneReplyPerSecond`). See §4.2 for the companion non-Heartbeat CONTROL-frame cap (D-61) and the combined authenticated-flood test (E20-20). | Bounded, not eliminated — see §4.2. | `security: mitmLabDos_authenticatedHeartbeatFlood1000PerSecond_phoneRepliesCappedSessionStaysUp` (E20-20) | AC-19 |
| Elevation of privilege | Peer negotiates a capability it doesn't actually support to unlock a feature path. | Capability set is explicit in `VersionHello`; an unrecognized/unsupported capability is never trusted to gate behavior beyond a client-visible advertisement (E12-07, E12-15). | None. | Covered by `VersionHello` acceptance tests (E12-07/15). | AC-04 |
| Tampering | Media ticket is intercepted or forged in transit on the CONTROL channel before the media connection uses it (see §4.15 for consumption-side abuse). | Ticket is CSPRNG 256-bit, single-use, 30 s expiry, never logged or persisted (D-25; E01-09, E60-08); confidentiality on the wire is the same TLS 1.3 guarantee as §4.1. | None beyond transport. | See §4.15's media-ticket tests. | AC-08 |

*(The protocol-hygiene "no debug path" threat that would otherwise sit here is covered once, generically, in §4.2.)*

### 4.5 Key rotation (KeyRotation / RotationAck / RotationReject)

Assets: the long-term SPKI pin at each peer.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing | `KeyRotation` sent before the handshake completes, during an open pairing window, or by a peer whose key isn't pinned. | Rotation is accepted only on an authenticated `Ready` session (D-24; E70-01, E70-04, E70-05); an unpinned peer's rotation attempt fails in the handshake itself, before rotation logic runs. | None. | `security: mitmLabRotation_keyRotationBeforeHelloComplete_rejectedTrustStoreUnchanged`, `mitmLabRotation_keyRotationInPairingWindow_rejectedTrustStoreUnchanged`, `mitmLabRotation_unpinnedPeerSendsKeyRotation_handshakeFailsNoPinAdded` | AC-15 |
| Tampering (replay / key claim) | A captured `KeyRotation` is replayed on a new session, or an attacker claims another paired peer's key as their "new" key. | Signature covers old key, new key, and the session's channel-binding value (`"tandem-rotate-v1" \|\| LP(old) \|\| LP(new) \|\| LP(cb)`, D-24); `DUPLICATE_KEY` rejects a new key already pinned to a different peer. | None. | `security: mitmLabRotation_keyRotationReplayedOnNewSession_rejectedTrustStoreUnchanged`, `mitmLabRotation_newSpkiOfOtherPairedPeer_rejectedDuplicateKey` | AC-15 |
| Repudiation / misuse | Rotation used to try to "launder" a stolen old private key into a fresh identity, i.e. treated as compromise recovery. | Explicit decision that rotation is **not** compromise recovery; a stolen old key must be handled by unpair + re-pair on both sides, not rotation (D-24). | If the owner rotates instead of unpairing after a suspected old-key compromise, an attacker who also holds the stolen old key cannot forge new rotations going forward, but any session the attacker completed before rotation remains valid until independently detected. Documented in §5. | Design review only (no automatable test for "owner chose the wrong recovery action"); mitm-lab suite proves the *protocol* can't be abused, not that the *owner* always chooses re-pair. | AC-15 |
| Denial of service | Grace pin kept alive indefinitely, or a multi-phone Mac rotation stalls waiting on one slow phone's ack, blocking the others. | Grace pin TTL ≤ 7 days (D-24); per D-34/E70-03, the Mac's listener identity switches only after *every* paired phone has acked — with two phones, one ack leaves the listener on the old identity (`macRotationInitiator_oneOfTwoPhonesAcked_listenerKeepsOldIdentity`, E70-03); each phone independently promotes its own pending pin on next handshake, with a 7-day Finish/Cancel choice on the Mac so one silent phone can't block the rest indefinitely (D-34; E70-11, E70-13). A pending Mac pin a phone never sees within 30 days is purged and the old pin stays primary (`androidRotationReceiver_pendingMacPinUnseen30Days_purgedOldPinKept`, E70-04). | The 7-day "Finish" path can unpair a phone that was merely offline (not compromised) for over a week; accepted per owner decision D-54. A phone also trusts *both* the primary and a pending Mac key simultaneously for up to 30 days before an unseen pending pin is purged — see the pending-key residual in §5. | `macRotationInitiator_oneOfTwoPhonesAcked_listenerKeepsOldIdentity` (E70-03); `androidRotationReceiver_pendingMacPinUnseen30Days_purgedOldPinKept` (E70-04); `security: mitmLabRotation_pendingMacKeyOfferedBeforeAllAcks_unackedPhoneKeepsOldPinOnly` (E70-09); `rotationE2e_twoJvmClientsOneNeverAcks_listenerKeepsOldIdentityBothStillConnect`, `rotationE2e_finishAfter7DaysVirtual_pendingClientHandshakeFailsAckedClientOnNewKey` (E70-10) | AC-15 |

### 4.6 Revoke

Assets: the trust-store record of a peer.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing | Attacker (or an unauthenticated/pairing-window connection) sends `Revoke` to delete a legitimate peer's trust record. | `Revoke` carries no fields and is accepted only on an already-trusted `Ready` session, never on a pairing candidate (D-23; E14-15, E14-19). | None. | `security: mitmLab_revokeOnPairingCandidateConnection_trustStoreUnchanged` | UC-07 |
| Repudiation / fail-open risk | Peer is offline when revoked; does the removed peer keep connecting? | Local deletion is immediate; remote deletion is best-effort. If the peer is offline, its trust record is deleted locally only — but the *next* connection attempt from that peer fails handshake closed because the local side no longer has its pin (Inv 3, 5; UC-07; `jvmHarness_macRevokesOfflinePhone_nextHandshakeFailsNoLongerPaired`, E14-20). Loopback offers no special privilege either: a revoked peer reconnecting over loopback with no pairing window open still fails the handshake with zero application bytes delivered (`revokedPeer_loopbackReconnectNoWindow_handshakeFailsZeroAppBytes`, E14-15). This is the network/protocol mitigation for **AC-09** (lost/stolen paired phone): once the owner revokes on the Mac, the stolen phone's subsequent handshakes fail pin-check closed exactly as in §4.1. The symmetric case — the phone unpairs while the Mac is offline, then never dials that Mac again and a forced dial fails the pin check — is the network half of **AC-12** (lost/stolen Mac; `jvmHarness_phoneUnpairsWhileMacOffline_neverDialsAndForcedDialFailsPin`, E14-20); the Mac-side cached-data half of AC-12 is E02-08. Full local-device-loss analysis otherwise (what a stolen phone/Mac itself can still do offline) is E02-08. | None at the protocol layer; "no longer paired" never auto-deletes trust on receipt of an unauthenticated message (D-23), so an attacker cannot forge the reverse (fake-revoke-to-regain-trust) direction either. | `jvmHarness_macRevokesOfflinePhone_nextHandshakeFailsNoLongerPaired`, `jvmHarness_phoneUnpairsWhileMacOffline_neverDialsAndForcedDialFailsPin` (E14-20); `revokedPeer_loopbackReconnectNoWindow_handshakeFailsZeroAppBytes` (E14-15); mitm-lab-style handshake-fails test per UC-07 acceptance. | AC-09, AC-12 (partial), UC-07 |

### 4.7 NOTIFY channel

Assets: notification title/text/actions, `RemoteInput` reply text, per-app icons.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Tampering | An authenticated-but-malicious peer forges a `NotificationAction` (fake `replyText`/`actionIndex`) to fire an arbitrary `PendingIntent`. | Wire-level: field/size caps (D-21). The receiving-side confused-deputy defense (immutable, explicit `PendingIntent`s only, D-28; E30-09) is the full mitigation but belongs to E02-08's Android-IPC chapter; recorded here because the trigger arrives over this channel. | Full IPC-level analysis is E02-08 (AC-16). | `E30-09` unit/integration tests; full coverage tracked in E02-08. | AC-16 (partial), AC-19 |
| Information disclosure | `VISIBILITY_SECRET` content, or any notification text/body, reaches the Mac or a log beyond the owner's opt-in. | App-name-only by default; content forwarded only after explicit opt-in (F-5.4; E30-11). Logs never contain notification text (Inv 7; E00-17, E00-27, D-31). | None within the opt-in model. | `security: pcapCanary_companionCanaryNotification_absentFromCapture`, `logAudit_companionCanaryNotificationSession_zeroHitsInBothLogs` | AC-02, AC-10 |
| Denial of service | Malicious/compromised paired peer floods notification posts or rapid updates to overwhelm the channel or the Mac UI. | Rate limiting and coalescing of rapid updates (E30-12); per-channel flow-control credits keep a NOTIFY flood from starving other channels and vice versa (F-3.2; E11-07, E11-08). | Bounded by rate limit, not eliminated — a compromised paired peer can still post at the allowed rate. | `E11-09`/`E11-10` starvation regression tests. | AC-19 |
| Spoofing (display) | Peer-supplied app name, sender name (MessagingStyle), or notification text contains bidi overrides, control/zero-width characters, or is oversized, to spoof the Mac UI. | `DisplayStringSanitizer` applied to every peer-supplied string before rendering, vector-tested (D-22; E01-23, E14-21, E14-22). | None within the vector set. | Untrusted-string vector suite (E01-24, E14-21/22). | AC-14 |

### 4.8 CLIPBOARD channel

Assets: clipboard text, which may include secrets the owner just copied.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Tampering (echo loop) | A synced clip is echoed back to its origin, or a spoofed origin tag causes a loop. | Origin tag plus content hash on both sides (F-6.3; E31-08, E31-14). | None. | `E31-10` clipboard exit test ("no echo loop"). | AC-19 |
| Information disclosure | Concealed/Transient pasteboard items (password managers) reach the wire. | Concealed/Transient type check skips the send at the source, before any network write (D-29; E31-03). | None — the check runs before the item ever enters the mux. | `security: pcapCanary_clipboardCanaryMacToPhone_absentFromCapture`, `logAudit_clipboardAndConcealedCanaries_zeroHitsInBothLogs` | AC-02, AC-10 |
| Denial of service | Oversized or repeated large clips sent to exhaust bandwidth/memory. | 1 MiB cap enforced before send; a clip one byte over the cap produces no frame at all and a "too large" toast, not a truncated send (F-6.3, UC-12; E31-06). | None. | `clipboardSender_oneByteOver1MiB_noFrameAndTooLargeToast` (E31-06) | AC-19 |

### 4.9 FILES channel (including photos)

Assets: file bytes, filenames, destination paths on disk.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Tampering (path traversal) | `FileOffer.name` contains path-traversal sequences, hidden/reserved names, or otherwise escapes the destination directory. | Shared `FilenameSanitizer` with vector-tested rules on both platforms (E40-02, E40-16, E40-17); receiver writes to a temp file and atomically moves only after full SHA-256 verification (F-7.1). | None within the vector set. | `E40-02` conformance vectors; UC-14 acceptance ("filenames sanitized, no path traversal, no hidden/reserved names; partial files never visible in the destination"). | AC-14, AC-19 |
| Tampering (data corruption) | Chunk stream is corrupted, reordered, or truncated mid-transfer. | Per-chunk sequence numbers, final whole-file SHA-256 check (F-7.1); resumable-by-offset re-verifies on reconnect (E40-08, E40-19). | None. | `E40-14` (4 GB forced-disconnect transfer, hash match). | AC-19 |
| Denial of service | Unbounded concurrent offers or size to exhaust disk/memory/bandwidth. | Caps: 64 GiB max size, ≤ 4 pending offers, ≤ 2 active per direction, auto-accept only ≤ 1 GiB and off by default (D-21, D-44; E40-07, E40-18); disk-space pre-check before accept. | Bounded by caps, not eliminated. | `E40-15` flow-control no-starvation test; `E40-14` forced-disconnect test. | AC-19 |
| Elevation of privilege | Auto-accept writes an attacker-influenced file to disk without a prompt, from a compromised-but-still-pinned paired peer. | Auto-accept is an explicit opt-in setting, size-capped at 1 GiB, off by default (D-21, D-44). | If the owner enables auto-accept, a compromised paired peer can push files up to the cap unattended. Documented in §5. | Covered by the E40-07/18 accept-flow unit tests. | AC-19 |
| Denial of service (thumbnail flood) | Rapid/repeated `ThumbRequest` traffic to exhaust decode/IO work generating photo thumbnails. | ≤ 8 outstanding `ThumbRequest`s per peer; the 9th concurrent request is rejected `BUSY` before any decode work starts (D-21; E41-04). | None within the cap. | `thumbGeneration_ninthOutstandingRequest_busyErrorNoLoad` (E41-04) | AC-19 |

### 4.10 SMS channel

Assets: SMS thread/message content, phone numbers.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Tampering / abuse | A compromised-but-authenticated paired peer sends excessive or malformed SMS reads/sends. | Caps: ≤ 1600 chars per message, ≤ 10 sends/min, one sync in flight (D-21, D-44; E50-04, E50-03, E50-13). | Bounded, not eliminated — a peer within the ≤ 10/min cap can still send unwanted messages, including to premium-rate numbers (real monetary cost to the owner). Accepted because the peer is, by definition, already trusted (see §6 Assumptions). | Unit fixtures under E50-04; `security: mitmLab_smsSendBurst20In60s_atMost10SentRestRateLimited`, `mitmLab_smsBodyOver1600Chars_failedTooLongNoSmsSent` (E50-11) | AC-19 |
| Information disclosure | SMS content or phone numbers reach a log. | Inv 7; shared sensitive-symbol list includes `smsBody`, `smsAddress` (D-31; E00-17, E00-27). | None within the symbol list's coverage. | `security: logAudit_jvmClientSmsCanarySession_zeroCanaryMatches`, `logAudit_physicalPhoneSmsCanarySession_zeroMatchesInLogcatAndMacLog` | AC-10 |
| Denial of service | Sync watermark manipulation or duplicate resend flood. | Incremental sync strictly by `_id` watermark, one sync in flight at a time (E50-03, E50-13). | None. | Unit coverage under E50-03/13. | AC-19 |

### 4.11 CONTACTS channel

Assets: contact name, numbers, emails, photo thumbnail.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Information disclosure | Contact PII reaches a log. | Inv 7 (E00-17, E00-27, D-31). | None. | `security: logAudit_jvmClientContactsCanarySession_zeroCanaryMatches`, `logAudit_physicalPhoneContactsCanarySession_zeroMatchesInLogcatAndMacLog` | AC-10 |
| Spoofing (display) | Contact/caller name contains bidi/control/zero-width characters or is oversized, to spoof the Mac UI. | `DisplayStringSanitizer` applied before rendering (D-22; E01-23, E14-21, E14-22). | None within the vector set. | Untrusted-string vector suite. | AC-14 |
| Denial of service | Bulk/duplicate sync flood. | Incremental sync via updated-timestamp watermark plus deletes (E51-02, E51-05). | None. | Unit coverage under E51-02/E51-05. | AC-19 |

### 4.12 CALLS channel

Assets: caller ID, call state, dialed number.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Tampering (dangerous dial strings) | `PlaceCallRequest.address` carries an MMI/USSD code (e.g. `**21*123#`) to trigger a carrier feature-code instead of a normal call. | Address MUST match `^\+?[0-9]{3,20}$` after removing spaces/dashes; no `*`/`#`/`,`/`;`; `INVALID_NUMBER` otherwise (D-21; E01-22, E52-05). | None within the pattern's coverage; a carrier that accepts a dialable-but-unexpected number sequence outside this pattern is out of scope. | Dial-string fixtures under E52-05; `security: mitmLab_placeCallMmiCodeAddress_invalidNumberNoCallPlaced` (E52-09) | AC-19 |
| Denial of service | Rapid repeated `PlaceCallRequest`. | ≤ 1 request per 5 s, `RATE_LIMITED` otherwise (E52-05). | None. | E52-05 unit fixtures; `security: mitmLab_placeCallBurst5In5s_oneCallPlacedRestRateLimited` (E52-09) | AC-19 |
| Information disclosure | Caller ID / call metadata reaches a log. | Inv 7 (D-31). | None. | `security: logAudit_jvmClientCallCanarySession_zeroCanaryMatches`, `logAudit_phoneCallCanarySession_zeroMatchesInLogcatAndMacLog` | AC-10 |
| Spoofing (display) | Forged caller-name display. | `DisplayStringSanitizer` (D-22; E01-23, E14-21, E14-22). | None within the vector set. | Untrusted-string vector suite. | AC-14 |

### 4.13 INPUT channel

Assets: on-phone UI and data reachable via `AccessibilityService`; the invariant-8 consent
boundary.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Elevation of privilege | `INPUT` frames arrive with no active user-started mirror session (or referencing a stale/ended one). | Inv 8: authorization gate checks a live session id and a persistent on-phone indicator before every dispatch, independent of the sender's identity (E62-06). | None — this is the primary defense the feature relies on. | `security: mitmLab_inputWithNoActiveMirrorSession_notInjectedAndLogged`, `mitmLab_inputWithStaleSessionReference_notInjectedAndLogged`, `mitmLab_inputAfterMirrorStopped_notInjectedAndLogged` | AC-06 |
| Tampering | Out-of-range coordinates, or raw-key-event-shaped payloads instead of field-scoped text ops. | No raw key events (only `TextEdit` ops with field ranges); coordinate/field range validation; out-of-range input is dropped, never clamped (D-27; E62-01, E62-03, E62-06). | None within validated ranges. | `security: mitmLab_inputOutOfRangeCoordinates_droppedNotClamped` | AC-19 |
| Denial of service | Input flood to overload the accessibility dispatcher or starve other channels. | 120 events/s cap (D-27); channel-level flow-control credits (F-3.2). | Bounded by the cap; a sustained flood at the cap can still degrade responsiveness. | `security: mitmLab_inputFlood1000PerSecond_atMost240Injected` | AC-19 |
| Information disclosure | Typed/dropped `SET_TEXT` content reaches a log. | Inv 7; a dropped `SET_TEXT` canary must never appear in logs. | None. | `security: logAudit_droppedSetTextCanary_absentFromLogs` | AC-10 |
| Tampering (indicator spoofing) | A malicious foreground app on the phone draws its own overlay on top of, or otherwise obscures/detaches, the persistent on-phone remote-input indicator so the owner doesn't notice an active session. | The indicator renders as a `TYPE_ACCESSIBILITY_OVERLAY` (a system overlay type other apps cannot draw above); input dispatch is gated on the indicator's own attached/visible state, so if it is ever detached, in-flight and subsequent `INPUT` frames are dropped rather than assumed-shown (Inv 8; E62-06). | None within the tested detachment path. | `inputGate_indicatorOverlayDetached_frameDropped`, `remoteInputIndicator_otherAppOverlayShown_accessibilityOverlayStaysTopmost` (both E62-06) | AC-06 |

Residual (tracked fully in E02-08): an app that sets `FLAG_SECURE` renders black in the mirrored
video, but the video redaction is not itself an input-authorization boundary — the phone still
receives and can inject `INPUT` events into that app during an active, indicator-shown session.
Recorded here because it is directly adjacent to this channel's invariant-8 boundary; see §5.

### 4.14 STATUS channel

Assets: battery/network/signal metadata, `Ring`/`RingStop` commands.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Information disclosure | Status metadata (battery, network type, signal) is low-sensitivity but still crosses the network. | Same TLS 1.3 confidentiality guarantee as every other channel (Inv 1, 2). | None. | Covered by §4.1's pcap-audit tests. | AC-02 |
| Denial of service | `Ring` spam from a compromised-but-authenticated paired peer to drain battery or annoy the owner. | `Ring`/`RingStop` are simple no-payload commands usable only by an already-paired peer; `Ring` is idempotent while already ringing (a second `Ring` is a no-op, not a second alarm) and the alarm starts at most twice per rolling 10 s window (D-62; E23-06); owner can `Stop` from the Mac or dismiss on the phone within 1 s (F-4.4); round-trip behavior tested (E23-08). | A compromised paired Mac can still trigger up to two alarm starts per 10 s indefinitely; low severity, owner-visible and dismissible, now cooldown-bounded rather than unbounded. Documented in §5. | `ringController_ringWhileAlreadyRinging_noSecondAlarmStart`, `ringController_tenRingsIn10s_alarmStartedAtMostTwice` (E23-06); `ringFlood_macSends20RingsIn5s_phoneAlarmStartedAtMostTwice` (E23-08) | AC-19 |
| Tampering | Publish-on-change abused to spam status updates. | ≤ 60 s throttle unless a value changed (E23-03). | None. | E23-03 unit fixtures. | AC-19 |

### 4.15 Media connection (media mTLS + ticket binding)

Assets: the H.264 mirrored-screen stream, the media ticket.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing / hijack | Attacker, or a client from a different session, opens a media connection presenting a missing, reused, expired, or another session's ticket. | Media ticket is single-use, 256-bit, 30 s expiry, bound to the issuing control session by the `MediaTicket` issuer/validator (D-25; E60-08). | None. | `security: mitmLab_mediaHelloWithoutTicket_rejectedAfterHandshake`, `mitmLab_mediaReusedTicket_rejectedAfterHandshake`, `mitmLab_mediaTicketAfter31s_rejectedAfterHandshake`, `mitmLab_mediaTicketFromEndedSession_rejectedAfterHandshake`, `mitmLab_mediaTicketOnOtherPeersClientCert_rejectedAfterHandshake` | AC-08 |
| Tampering | Malformed or oversized `MediaFrame` fragments break the reassembler. | Fragments ≤ 960 KiB, ≤ 8 per access unit, contiguous, ≤ 8 MiB reassembled; violations close `MALFORMED_FRAME`; fuzzed (D-26; E61-01, E61-14, E71-13). | Bounded by the fuzz campaign, same caveat as §4.2. | `security: frameParserFuzz24h_libFuzzerCampaign_zeroCrashesOrHangs` (media-scoped target under E71-13/E71-04) | AC-07, AC-19 |
| Information disclosure | Passive capture of the mirrored screen contents. | Media connection is full mTLS with the same identities/pins as control, no weaker cipher suite, and is accepted on the same single listener as control — there is no second, separately-configured "media listener" to misconfigure (D-03, Inv 2; F-3.3; E12-01, E60-03, `mediaAcceptor_duringActiveMirror_exactlyOneListeningSocket`). | None. | `security: pcapAudit_activeMirrorSession_onlyTls13RecordsOnBothConnections`, `pcapAudit_activeMirrorSession_allTandemFlowsOnSinglePort`, `pcapAudit_canaryOnMirroredScreen_zeroPlaintextOccurrences`, `canaryProcedure_mirrorStep_captureContainsMediaTraffic`; `mediaAcceptor_duringActiveMirror_exactlyOneListeningSocket` (E12-01/E60-03) | AC-02 |
| Denial of service | `MediaHello` never sent after ticket issuance, or the connection held open indefinitely. | 5 s `MediaHello` deadline enforced by the media acceptor on the single listener (D-03, D-20; E01-22, E60-03), closed `PROTOCOL_TIMEOUT`. | None. | `security: mitmLab_mediaConnectionNoHelloFor6s_closedProtocolTimeout`; `mediaAcceptor_noMediaHelloWithin5s_closesProtocolTimeout` (E60-03) | AC-13 |
| Denial of service / hijack | Multiple media connections opened against the same control session, e.g. to multiply bandwidth/CPU use, or because a cloned identity key is used concurrently. | At most one open media connection per control session (E01-22; E60-04, `mediaRegistry_perControlSession_atMostOneOpenMediaConnection`). | If a peer's private key is cloned (stolen and used concurrently — key extraction itself is assumed hard, see Assumptions), the clone presents the same valid certificate as the original; TLS accepts it, and the *newer* connection for that session's peer SPKI takes the one media slot (the same "newer Ready session replaces the older one" rule as control sessions, E01-22) — cloning a key does not grant an *extra* media stream, but it can still silently kick the legitimate device's stream. Documented in §5. | `mediaRegistry_perControlSession_atMostOneOpenMediaConnection` (E60-04) | AC-08 |
| Elevation of privilege | Capture/streaming starts without the phone owner's consent. | Inv 8: a Mac-side click only posts an on-phone prompt and never itself starts a local capture action; `MediaProjection` consent and ticket issuance both require the owner's on-phone accept before capture starts (UC-22; E61-02, `mirrorSessionStarter_noLocalStartAction_neverLaunchesConsent`; UI-level request/decline states in E61-12, E61-16). | None. | `mirrorSessionStarter_noLocalStartAction_neverLaunchesConsent` (E61-02); E61-12, E61-16 request/decline-state tests; UC-22 acceptance ("a Mac mirror request without an on-phone accept never starts capture or issues a ticket"). | AC-06 |

### 4.16 Discovery / Bonjour (mDNS) and the BLE hint (ADR E20-13)

Assets: the Mac's presence/address hint; carries no key material by design.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing | Attacker advertises a spoofed `_tandem._tcp` service replaying a paired Mac's *currently valid* rotating TXT id (which, by design, does match) at a different address/key, to lure the phone into dialing it. | Discovery only ever supplies a candidate address to the reconnect strategy; the mTLS pin check runs independently and rejects the impostor's key regardless of a matching id (Inv 1, 3; E21-05, E21-06). | The phone will attempt (and fail) a doomed connection to the impostor; this is accepted by design — the pin check, not discovery matching, is the trust boundary. | `security: spoofedAdvertisement_validIdWrongKey_pinCheckFailsNoAppData` | AC-05, AC-04 |
| Information disclosure | Cross-day tracking of the Mac via a stable discovery identifier. | TXT record contains only `v=1` and a daily-rotating `HMAC(macSpki, dayIndex)` (per E01-08); the service instance name is derived from the same rotating id, no Mac name/user name/fingerprint (F-3.5; E21-02). | The mDNS **SRV/A records still carry the Mac's OS-assigned local hostname**, which Tandem does not control and which does not rotate; an observer can correlate presence across days via the hostname even though the TXT/instance name rotate. Mitigation is user-level (rename the Mac's local hostname), not enforced by Tandem. Recorded in §5. | Rotating-id vectors/conformance (E01-20, E15-01, E15-02); `dnsSdBrowse_acrossUtcMidnight_txtIdAndInstanceNameChanged` (manual gate). | AC-05 |
| Tampering | Malformed TXT record or instance name fed to the resolver to crash it. | Unmatched or malformed ids are ignored without an exception (E21-05 acceptance). | None within the tested fixture set. | `unit: pairedMacMatcher_malformedId_ignoredWithoutException` | AC-07 (adjacent) |
| Denial of service | Flooding the network with fake `_tandem._tcp` advertisements. | Discovery only ever supplies a candidate address; it never bypasses per-IP pre-auth admission control on the real connection attempt (D-20 applies at the listener). | Worst case is wasted connection attempts, each closed by admission control; low severity. | Covered transitively by §4.1's admission-control tests. | AC-13 (adjacent) |
| Spoofing / information disclosure (BLE hint, not yet in v1) | If ADR E20-13's option (b) is adopted (Mac emits a BLE advertisement the phone observes to self-trigger a reconnect dial), a nearby attacker could try to spoof or track that advertisement. | Per E20-13's own acceptance criterion, if option (b) is accepted the advertisement MUST use a daily rotating identifier derived like F-3.5, a random BLE address, and no device name or service data beyond the rotating id; BLE never carries application data or keys (Inv 1); no phone-side GATT server (option (c) rejected outright as equivalent to a phone listener, Inv 4). | Decision is explicitly deferred and data-driven (v1 default is *not* to ship BLE, pending E20-12's reconnect-latency data); this row is recorded proactively so a STRIDE row exists before any BLE follow-up issue starts, per E20-13's acceptance text. Must be revisited once E20-13 resolves. | No test yet — spike/ADR not started. | AC-04 (reconnect-adjacent) |

### 4.17 On-device sources feeding the mux

Each source below crosses B7 (an OS-granted permission surface into the wire). This chapter
covers only the flow *into* the Envelope; the OS-permission/IPC side of each source is E02-08.

| Source → Channel | STRIDE | Threat | Mitigation | AC |
|---|---|---|---|---|
| NotificationListenerService → NOTIFY | Tampering/DoS | A third-party app posts a notification crafted to break parsing (oversized title, malformed `MessagingStyle`) before it reaches the wire. | Field/size caps applied at capture; Tandem's own and system-noise notifications filtered out before entering the mux (D-21; E30-05, E30-12, F-5.1). | AC-19 |
| Clipboard entry points → CLIPBOARD | Tampering/DoS | Oversized or high-frequency clip captured from an entry point. | 1 MiB cap enforced at the sender before any frame is built (E31-06, `clipboardSender_oneByteOver1MiB_noFrameAndTooLargeToast`); every entry point requires an explicit owner action (no passive background read on Android 10+, F-6.2). | AC-19 |
| MediaStore/SAF → FILES/photos | Tampering | Crafted filename/path returned by the picker or content provider. | `FilenameSanitizer` applied before a `FileOffer` is ever created (E40-02, E40-16). | AC-19 |
| Telephony provider → SMS | Information disclosure/DoS | Provider read outside the declared watermark window, or watermark manipulation. | Incremental sync strictly by `_id` watermark, one sync in flight (E50-03, E50-13). | AC-19 |
| ContactsContract → CONTACTS | Information disclosure | Bulk read of fields beyond the documented set. | Read-only sync limited to the documented field set only (name, numbers, emails, thumbnail; E51-02). | AC-19 (adjacent) |
| TelecomManager → CALLS | Tampering | See §4.12: dial-string sanitization applied at the boundary before a `PlaceCallRequest` is ever sent, and again on receipt. | E52-05. | AC-19 |
| MediaProjection → media connection | Elevation of privilege | Capture starts without fresh per-session consent. | Android-enforced consent dialog per session (Inv 8; E61-02); ticket not issued until accepted (UC-22, `mirrorSessionStarter_noLocalStartAction_neverLaunchesConsent`). | AC-06 |
| AccessibilityService ← INPUT (dispatch) / Mac mouse-keyboard capture → INPUT (source) | Tampering | Coordinate-mapping error targets the wrong on-phone element. | Coordinate mapping (rotation, letterboxing) is a pure, vector-tested function (E62-03); the receiver-side range/field validation (§4.13) is the authoritative gate regardless of sender-side correctness. | AC-19 |

---

## 5. Residual risk register

Accepted risks, cross-referenced to the decision or issue that accepted them:

1. **mDNS SRV/A hostname leak.** The Mac's OS-assigned local hostname is visible in mDNS SRV/A
   records regardless of Tandem's own rotating TXT id and instance name, and does not rotate.
   Mitigation is user-level (rename the Mac's local network hostname), not enforced by Tandem
   code. (§4.16; D-33; E21-02 note.)
2. **QR capture during the pairing window is best-effort, and a captured secret lets an attacker
   race the owner or leave a dangling Mac record.** macOS screen-capture exclusion of the QR
   window is best-effort, not an OS guarantee. An attacker who captures the secret can run their
   own device through the whole pairing flow and would see a matching confirmation code; the real
   defenses are the Mac dialog's default-Don't-Pair button (D-16; E14-08) and the single
   in-flight candidate slot (D-18; E12-02), which force the attacker and the owner's real phone to
   contend for one slot and one visible confirmation at a time. Residual: the owner can still
   click "Pair" without checking the shown code/name, and because the Mac commits the peer's
   fingerprint on its own Accept click (E14-08) *before* the phone-side owner confirmation commits
   the Mac's key (E14-05), an accepted-but-never-phone-confirmed pairing leaves a dangling Mac
   trust record until the owner notices and revokes it (E14-14). Full local-attacker analysis
   (loopback, screen recording, physical access) is E02-08's chapter (AC-17). (§4.3.)
3. **Rotation is not compromise recovery.** If the owner rotates instead of unpairing after a
   suspected old-key compromise, sessions the attacker already completed with the stolen old key
   before rotation remain valid until independently detected; going forward the attacker cannot
   forge new rotations. (§4.5; D-24.)
4. **7-day rotation "Finish" can unpair an innocently offline phone; pending-key window is up to
   30 days.** A phone that hasn't acknowledged a Mac-initiated rotation within 7 days is dropped
   ("Finish") rather than left on a stale pin indefinitely, even if it was merely offline (not
   compromised); accepted per owner decision D-54 (`rotationE2e_finishAfter7DaysVirtual_*`,
   E70-10). Separately, a phone trusts *both* its primary Mac pin and a pending Mac pin
   simultaneously for up to 30 days before an unseen pending pin is purged
   (`androidRotationReceiver_pendingMacPinUnseen30Days_purgedOldPinKept`, E70-04) — this is a
   30-day window during which a pending key, if it were ever attacker-influenced before being
   offered, would already be recognized (though not yet primary). (§4.5; D-34.)
5. **Auto-accept file transfers.** When the owner opts in (off by default), a compromised
   paired peer can push files up to the 1 GiB auto-accept cap unattended. (§4.9; D-21, D-44.)
6. **Ring/RingStop abuse by a compromised paired peer is cooldown-bounded, not eliminated.**
   `Ring` is idempotent while already ringing and the alarm starts at most twice per rolling 10 s
   window (D-62; E23-06, E23-08); a compromised paired peer can still trigger that many alarm
   starts indefinitely. Low severity, owner-visible and dismissible within 1 s either side.
   (§4.14.)
7. **BLE reconnect hint is undecided for v1.** ADR E20-13's STRIDE coverage (§4.16) is
   preliminary; the option is not expected to ship in v1 and must be revisited once E20-12's
   reconnect-latency data resolves the ADR.
8. **A doomed connection attempt to a discovery impostor is not prevented, only made harmless.**
   A spoofed advertisement replaying a paired Mac's valid rotating id will cause the phone to
   attempt a connection; the pin check then fails it closed. This is accepted by design — the
   fix is the pin check, not preventing the attempt. (§4.16.)
9. **Feature-channel abuse by an already-trusted, but compromised, paired peer is bounded, not
   eliminated.** SMS/CALLS/NOTIFY/FILES/STATUS rate and size caps (D-21, D-44, D-60, D-61) limit
   the blast radius of a compromised paired peer; a peer operating within its cap can still send
   unwanted messages, calls, files, or dial/text premium-rate numbers within the SMS/CALLS caps.
   This is inherent to the trust model (see Assumptions, §6).
10. **Traffic analysis / app fingerprinting.** TLS 1.3 encrypts certificates and application
    data, but a passive local observer can still: identify the app via the cleartext ClientHello's
    ALPN value (`tandem/1`) and the fixed listening port; infer which feature is active from
    record-length/timing patterns (e.g. a steady large stream suggests mirroring); and, from mDNS
    browse/advertise traffic, learn that a Tandem user is present on the network at all, without
    learning any content. No protocol-level padding/cover traffic is planned for v1. (§4.1, §4.16.)
11. **`PairRejected` timing side-channel.** The wire-visible rejection reason is collapsed to two
    codes (D-17), but the *response time* is not currently equalized across rejection paths (no
    window open vs. a full constant-time proof compare before rejecting), so a patient attacker
    could in principle infer which path was taken from latency alone. (§4.3.)
12. **Cloned-key session/media "kick".** A control session is one-per-peer-SPKI (a newer `Ready`
    session replaces the older one, E01-22) and a media connection is one-per-control-session
    (E60-04); if a peer's private key were ever cloned, the clone does not get an *additional*
    session/stream, but it can silently take over (kick) the legitimate device's existing one.
    Detecting the clone itself is out of scope — key extraction is assumed hard (see Assumptions).
    (§4.1, §4.15.)
13. **`FLAG_SECURE` apps still receive input while mirrored black.** The mirrored video redacts
    to black for apps that set `FLAG_SECURE`, but that redaction is not an input-authorization
    boundary: the phone still receives and injects `INPUT` events into such an app during an
    active, indicator-shown session. Full treatment is E02-08's local-surface chapter; recorded
    here because it sits directly against this channel's invariant-8 boundary. (§4.13.)

## 6. Assumptions

- The Owner is the sole legitimate operator of both devices; this model does not defend against
  the Owner intentionally misusing their own paired devices.
- Both platforms' native TLS stacks (Network.framework / Conscrypt) correctly implement TLS 1.3,
  enforce `CertificateVerify`, and correctly implement the RFC 9266 exporter, as validated by the
  Phase 0 spikes (E03-01, E03-03, E03-04). If a spike is a no-go, D-35 and `E03-06`'s fallback
  criteria govern the switch to the in-band challenge (D-15), and every channel-binding row in
  §4.3/§4.5 above must be re-verified against the fallback.
- AndroidKeyStore (StrongBox/TEE) and macOS Keychain/Secure Enclave correctly protect private
  keys from extraction; hardware-level key-extraction attacks are out of scope for this document.
- The local network (Wi-Fi) may contain an active adversary (AC-01, AC-02, AC-04, AC-05, AC-13
  all assume this); this model does not assume a trusted LAN.
- A "paired peer" is trusted up to the invariants and per-channel caps documented here; a fully
  compromised paired peer (malware on the Mac or the phone) can do anything the protocol permits
  that peer to do. Bounding that blast radius is the purpose of the caps in D-21, D-26, and D-27
  — not preventing a compromised-but-authenticated peer from acting within them.
- `docs/protocol/SPEC.md` (E01) had not been written when this chapter was drafted; message and
  field detail is sourced from the PRD, `decisions.md`, and backlog issue descriptions that will
  become SPEC sections. This document must be cross-checked against SPEC.md once E01 lands.
- E02-08 (Android IPC, Mac local surfaces, storage, logs/crash reports, CI/supply chain) is a
  separate, dependent backlog issue. AC-12, AC-16, AC-17, and AC-18 are intentionally not fully
  covered here — only touched where they overlap a network/protocol flow (see the "partial" AC-16
  and AC-17 rows above) — and will be completed in that chapter.

## 7. Abuse-case coverage index (this chapter)

| AC | Referenced in |
|---|---|
| AC-01 | §4.1, §4.4 |
| AC-02 | §4.1, §4.7, §4.8, §4.14, §4.15 |
| AC-03 | §4.3 |
| AC-04 | §4.1, §4.16 |
| AC-05 | §4.16 |
| AC-06 | §4.13, §4.15, §4.17 |
| AC-07 | §4.2, §4.3, §4.15, §4.16 |
| AC-08 | §4.4, §4.15 |
| AC-09 | §4.6 |
| AC-10 | §4.7, §4.8, §4.10, §4.11, §4.12, §4.13 |
| AC-11 | §4.2 |
| AC-12 | §4.6 (partial — network half only; Mac-side cached-data half in E02-08) |
| AC-13 | §4.1, §4.3, §4.15, §4.16 |
| AC-14 | §4.7, §4.9, §4.11, §4.12 |
| AC-15 | §4.5 |
| AC-16 | §4.7 (partial — full coverage in E02-08) |
| AC-17 | §4.3 (partial — full coverage in E02-08) |
| AC-19 | §4.2, §4.7, §4.8, §4.9, §4.10, §4.11, §4.12, §4.13, §4.14, §4.15, §4.17 |
| AC-20 | §4.3 |

AC-18 is not referenced in this chapter; it concerns supply-chain/telemetry, entirely within
E02-08's scope (CI/supply chain), which this issue explicitly excludes (D-33). AC-12 now has a
partial row here (§4.6): the network-protocol half (phone unpairs while the Mac is offline, then
never dials that Mac again and a forced dial fails the pin check) is in scope for E02-01; the
Mac-side cached-data half (what a stolen Mac's local SMS/contacts/thumbnail caches still expose)
remains E02-08's.

---

# Chapter 2 — Local platform surfaces, storage, logs, CI and supply chain

STRIDE analysis of every local surface outside the wire protocol, per backlog issue **E02-08**
(depends on chapter 1, E02-01; split recorded in D-33). Same conventions as chapter 1 (§1): **Inv
N**, **D-NN**, **E##-##**, **AC-##**, and the same six-column table (STRIDE, Threat, Mitigation,
Residual risk, Verifying test, AC). Where a surface is already touched by a chapter 1 row (cross-
referenced explicitly below), this chapter either completes it or points back rather than
repeating it.

## 8. Scope and method

Per E02-01's scope split (D-33), this chapter covers what chapter 1 explicitly excluded: Android
IPC internals (exported components, PendingIntents, tapjacking, backup/device-transfer
extraction), Mac local surfaces (loopback and other local reachability of the listener, QR
capture during the pairing window, the share-extension queue, Finder Services, NSPasteboard
writes, notification presentation and the lock screen), on-disk storage (Keychain identity/trust
items, GRDB SMS/contacts stores, thumbnail/icon caches, transfer temp files, downloaded files,
unpair purge, lost/stolen phone and Mac), logs and crash reports, and CI/release (signing
secrets, secret scanning, test-only-code scanning, dependency supply chain, telemetry/egress).

## 9. Trust boundaries (chapter 2 additions)

| # | Boundary | Notes |
|---|---|---|
| B8 | Other apps on the phone ↔ Tandem's exported components, PendingIntents and FileProvider-served content | Untrusted: any installed app can send an intent to an exported component or a crafted share/PROCESS_TEXT intent (AC-16). |
| B9 | Other local processes/OS users on the Mac ↔ the listener (incl. loopback), the App Group queue, and the pairing QR window | Bounded, not trusted: no special exemption exists for "local," but no local-only attack surface beyond what chapter 1's pin check and admission control already cover is introduced either (AC-17). |
| B10 | OS keystore/keychain and on-disk stores ↔ physical possession of the device | The boundary a lost/stolen phone (AC-09) or Mac (AC-12) actually tests. |
| B11 | CI environment ↔ release signing secrets and the third-party dependency graph | Untrusted: a pull-request workflow, a compromised transitive dependency, or an unpinned Action (AC-18). |

## 10. Threat model per surface

### 10.1 Android IPC surfaces

Assets: exported components, PendingIntents Tandem creates and the third-party ones it fires,
the backup/device-transfer channel, the NotificationListenerService and AccessibilityService
bindings, Tandem's own FileProvider content.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Elevation of privilege | Another app starts or binds to a Tandem component it shouldn't reach (share/PROCESS_TEXT activities, the QS `TileService`, `NotificationListenerService`, `AccessibilityService`, the `BOOT_COMPLETED` receiver), or a component is exported by accident. | Every component is `exported="false"` unless listed in `tools/release-audit/android-exported.allowlist` with its guarding permission (`BIND_QUICK_SETTINGS_TILE`, `BIND_NOTIFICATION_LISTENER_SERVICE`, `BIND_ACCESSIBILITY_SERVICE`); the `BOOT_COMPLETED`/`MY_PACKAGE_REPLACED` receiver, which must be exported, additionally checks the intent action itself (D-28; E00-28, E20-08). | None within the allowlist's coverage; a new component not added to the allowlist fails CI rather than shipping silently exported. | `ci: exportedComponentCheck_unlistedExportedActivityFixture_checkFails` (E00-28); `unit: bootReceiver_explicitIntentOtherAction_startsNothing` (E20-08) | AC-16 |
| Tampering / EoP (confused deputy via intents and URIs) | A crafted `ACTION_SEND`/`ACTION_SEND_MULTIPLE`/`PROCESS_TEXT` intent carries a `file://` URI (reads another app's or Tandem's own private files), a `content://` URI whose authority is Tandem's own `FileProvider`, more than 20 streams, or a non-`CharSequence` extra. | Only `content://` URIs are accepted, `file://` is rejected outright, a URI whose authority belongs to Tandem's own package is rejected, shares are capped at 20 streams, and `PROCESS_TEXT` accepts only a `CharSequence` extra (E40-11, E31-06). | None within the vector set tested. | `unit: shareTarget_fileSchemeUriIntoAppDataDir_rejectedNoOffer`, `unit: shareTarget_ownFileProviderAuthorityUri_rejectedNoOffer`, `unit: shareTarget_twentyOneStreams_rejectedNoOffer` (E40-11); `unit: processTextActivity_nonCharSequenceExtra_sendsNothing` (E31-06) | AC-16 |
| Elevation of privilege (PendingIntent hijack) | A PendingIntent Tandem creates is mutable or wraps an implicit Intent, letting another app fill in extras or redirect it; separately, the one PendingIntent Tandem itself *fires* on the peer's behalf (a notification action/reply) is reconstructed from attacker-influenced fields. | `PendingIntentImmutable` lint requires `FLAG_IMMUTABLE` and an explicit-component Intent on every `PendingIntent.getActivity/getBroadcast/getService/getForegroundService` (`FLAG_MUTABLE` needs a named allowlist entry) (D-28; E00-28); the action Tandem fires is looked up locally by key/actionIndex from the original posted notification, not reconstructed from peer-supplied fields, and a reply's `RemoteInput` fill-in carries only the result keys, nothing else (E30-09). | None within the lint's coverage. | `ci: pendingIntentLint_mutableWithoutAllowlistFixture_lintFails`, `ci: pendingIntentLint_implicitIntentFixture_lintFails` (E00-28); `unit: actionExecutor_plainActionIndexZero_sendsPendingIntentOfActionZero`, `unit: actionExecutor_fillInIntent_containsOnlyRemoteInputResults` (E30-09) | AC-16, AC-19 |
| Elevation of privilege (tapjacking) | An overlay from another app is drawn over a Tandem activity (settings toggles, the Accessibility opt-in explanation, share/QS capture activities) to intercept a tap. | Every Tandem activity extends a `TandemActivity` base that sets `window.decorView.filterTouchesWhenObscured = true`; lint requires every activity to extend it (D-28; E00-28). | None within lint coverage. | `unit: tandemActivity_onCreate_decorViewFiltersTouchesWhenObscured`, `ci: activityBaseClassLint_activityNotExtendingTandemActivity_lintFails` (E00-28) | AC-16 |
| Information disclosure (backup / device-transfer extraction) | Cloud backup or Android's device-to-device transfer tool extracts the trust store, settings, or transfer temp files from a lost, stolen, or backed-up phone. | `allowBackup="false"`, `fullBackupContent="false"`, and `dataExtractionRules` excluding every domain (D-28; E00-28). | None within the fixture check's coverage. | `ci: mergedManifest_allowBackupTrueFixture_checkFails` (E00-28) | AC-16, AC-09 |
| Information disclosure (denied dangerous permissions) | The app requests permissions beyond its documented feature set (app-inventory scraping, drawing over other apps, full-screen intents, unscoped storage, side-loading, device-admin) that would widen the blast radius if the app were later compromised. | CI denies `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `USE_FULL_SCREEN_INTENT`, `READ_CALL_LOG` (unless allowlisted), `MANAGE_EXTERNAL_STORAGE`, `REQUEST_INSTALL_PACKAGES`, `WRITE_SETTINGS`, `READ_LOGS`, `BIND_DEVICE_ADMIN` in the merged manifest (D-28; E00-28). | None within the denylist's coverage. | `ci: deniedPermissionCheck_queryAllPackagesFixture_checkFails` (E00-28) | AC-16 |
| Elevation of privilege (NotificationListenerService / AccessibilityService opt-in) | The two highest-privilege Android surfaces are bound without the owner understanding why, or bind with a wider capability set than declared. | `NotificationListenerService` is guarded by `BIND_NOTIFICATION_LISTENER_SERVICE`; `AccessibilityService` requires an explicit opt-in settings screen naming the reason, is disabled by default, requires `BIND_ACCESSIBILITY_SERVICE`, and its declared capability set is checked against a fixed allowlist that excludes key-event filtering (Inv 8; E62-02). | None within the config allowlist's coverage. | `ci: accessibilityServiceConfig_declaredCapabilities_equalAllowlist`, `ci: mergedManifest_accessibilityService_requiresBindAccessibilityPermission` (E62-02) | AC-16, AC-06 |
| Information disclosure (screenshots / recent-apps thumbnails) | The OS or another app captures a screenshot or recent-apps thumbnail of a Tandem phone screen showing forwarded content (e.g. a synced SMS thread). | Deliberately **not** mitigated with `FLAG_SECURE`: no secret is rendered on the phone (the pairing secret lives on the Mac, not the phone), and `FLAG_SECURE` would also blank Tandem's own screens inside the Mac's mirrored view of the phone (E61) — an explicit trade-off recorded here per E00-28's own note. | Accepted residual: screenshots/recent-apps thumbnails of Tandem's phone screens can capture forwarded content, exactly like any other non-`FLAG_SECURE` Android app. See residual register item 19. | Design decision, no test (D-28; E00-28 note). | AC-17 (adjacent), AC-19 |

### 10.2 Mac local surfaces

Assets: local reachability of the listener, the pairing QR image, the share-extension queue,
the general pasteboard, notification presentation, lock-screen content.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing / EoP (other local users or processes) | A process or login session on the same Mac (not the network attacker of chapter 1, but literally local — another account, or malware running as the same user) opens a connection to the listener, including over loopback, hoping for a local-only trust exemption. | Admission control and the SPKI pin check apply identically regardless of source address; loopback gets no exemption from the pre-auth caps, the 10 s TLS deadline, or the pin check (E12-18, chapter 1 §4.1); a revoked or never-paired peer reconnecting over loopback with no pairing window open fails the handshake with zero application bytes delivered (E14-15). App Sandbox network entitlements (E22-04) bound what the Tandem process itself can do but do not restrict which local uid can dial 127.0.0.1 — the pin check, not the sandbox, is what actually protects here. | A genuinely multi-user Mac is outside the PRD's single-user target-user assumption (D-12); any local account can attempt the same connection a network attacker could, though it gains nothing without a valid pinned key. See residual register item 15. | `integration: listener_loopbackStalledTcpConnection_closedWithin11s`, `integration: listener_tenIdleLoopbackConnections_ninthAndTenthClosedOnAccept` (E12-18); `integration: revokedPeer_loopbackReconnectNoWindow_handshakeFailsZeroAppBytes` (E14-15) | AC-17 |
| Information disclosure (QR capture during the pairing window) | A local attacker (another local session, a screen-recording tool, or a shoulder-surfer) captures the pairing QR while the window is open. | The pairing window sets `NSWindow.sharingType = .none`, excluded from screenshots and screen sharing where macOS honours it, and offers no copy/save action for the QR image or payload (E14-11); a captured secret still requires winning the Mac-side confirmation dialog and the single in-flight candidate slot before it grants trust (D-16, D-18; chapter 1 §4.3). | `sharingType = .none` is best-effort, not an OS guarantee, and physical shoulder-surfing is not addressable in software at all. See residual register item 16 (cross-ref chapter 1 residual item 2). | `unit: pairingWindow_created_sharingTypeNoneAndNoCopyAction` (E14-11) | AC-17 |
| Tampering (share-extension queue injection) | The Share extension has no network entitlement and wakes the agent only via a payload-free Darwin notification, so the agent trusts whatever it finds in the shared App Group queue directory; a process able to write into that same container could plant a symlink, an entry resolving outside the queue directory, a non-regular-file entry, or more than 20 entries per request. | The agent accepts only regular files, no symlinks, resolving inside the queue directory, at most 20 per request and each within the 64 GiB cap; the extension's own entitlements are exactly app-sandbox and application-groups — no network, no keychain access group — so the extension itself cannot be the network-facing half of an attack (E40-22). | None within the validated entry set; still assumes no *other* process legitimately shares this Mac's App Group, which holds for a single Tandem install. | `unit: sendRequestQueue_symlinkEntry_rejectedNoOffer`, `unit: sendRequestQueue_entryResolvingOutsideQueueDir_rejectedNoOffer`, `ci: shareExtensionEntitlements_releaseBuild_exactlySandboxAndAppGroup` (E40-22) | AC-17, AC-19 |
| Tampering (Finder Services entry point) | The "Send to phone" Finder Services item processes whatever the invoking context puts on the service pasteboard; a pasteboard with no file URL, or an unexpectedly large URL list, could be fed to it. | The provider reads only file URLs from the service pasteboard and starts one FileOffer per file; a pasteboard with no file URL starts nothing; the same FILES-channel caps as chapter 1 §4.9 (D-21) still gate size/count regardless of entry point (E40-21). | None within the tested paths; this entry point has no remote/attacker-controlled input — it is a local Services-menu invocation by the owner. | `unit: servicesProvider_noFileUrl_noOfferAndErrorReturned` (E40-21) | AC-17 (adjacent) |
| Information disclosure (NSPasteboard writes) | Text received from the phone and written to the general pasteboard is picked up by a local clipboard-history tool that persists it beyond the owner's expectation, or a sensitive phone-side clip is written without its Concealed/Transient markers. | Received text over 1 MiB is rejected before writing; a `sensitive = true` `ClipboardText` is written with both `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` so clipboard managers and Tandem's own poller skip it (E31-13; D-29). | A non-sensitive clip is, by design, written to the ordinary shared pasteboard like any other paste — a local clipboard-history tool a co-user might have installed will see it; this is the general macOS clipboard trust model, not a Tandem-specific hole. | `unit: pasteboardWriter_sensitiveText_writtenWithConcealedAndTransientTypes`, `unit: pasteboardWriter_textOver1MiB_pasteboardUnchanged` (E31-13) | AC-17, AC-02 (adjacent) |
| Information disclosure (notification presentation / lock screen / icon cache) | Forwarded notification content is visible to anyone who can see the Mac's screen while locked, or the per-app icon cache leaks or serves stale data for an unpaired phone. | The Mac-side "hide content while locked" setting (off by default) collapses a presented notification to app-name-only while `isLocked`, with no re-post on unlock (E30-15); the icon cache registers with `PeerDataPurgeRegistry` so unpairing a phone deletes its cached icons, and an oversized/malformed `IconData` is discarded in favor of a placeholder rather than cached (E30-06; E14-13). | With the lock-content-hiding setting left off (its default), full notification content shows on the lock screen like any other macOS app's notifications — this mirrors the phone's own `VISIBILITY_SECRET` opt-in model (chapter 1 §4.7) rather than being Tandem-specific. | `unit: lockScreenHiding_enabledAndLocked_titleAppNameBodyEmpty` (E30-15); `unit: iconCache_peerUnpaired_iconsForPeerDeleted`, `unit: iconCache_iconOver64KiB_discardedPlaceholderUsed` (E30-06) | AC-10, AC-12 (adjacent) |

### 10.3 Storage

Assets: long-term identity private keys, the trust store, GRDB SMS/contacts stores, thumbnail
and icon caches, transfer temp files, downloaded files.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Information disclosure / EoP (identity key extraction) | An attacker with local access, including physical possession of a lost/stolen device, tries to export the long-term identity private key to impersonate the owner's device elsewhere. | Mac: P-256 key generated via `SecKeyCreateRandomKey`, stored in the data-protection Keychain in the app's own access group with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, marked non-extractable (`SecKeyCopyExternalRepresentation` fails on the stored key) (E10-05). Android: `AndroidKeyStore` P-256, StrongBox preferred, non-extractable by construction; the JVM-only `SoftwareIdentityKeyStore` test fake is scanned out of every release APK (E10-15, E00-30). Per spike E03-02, Secure Enclave backing is a **NO-GO for v1** — SE key generation fails in every configuration reachable outside a fully Xcode-provisioned, Apple-ID-signed build — so the Mac key stays Keychain-only, the PRD's own documented default (`docs/spikes/secure-enclave-identity.md`). | Key-extraction attacks against the Keychain/AndroidKeyStore hardware boundary itself are out of scope (chapter 1 §6 Assumptions). The Mac key is Keychain-protected but not Secure-Enclave-token-backed, a narrower hardware boundary than Android's StrongBox path when StrongBox is available on the device. | `integration: identityKey_hostedKeychainExportPrivateKey_copyExternalRepresentationFails` (E10-05); `ci: releaseApk_softwareKeyStoreClass_absentFromDex` (E10-15 / E00-30) | AC-09, AC-12 |
| Information disclosure (trust store contents) | Reading the on-disk trust store directly (bypassing the app) to learn paired-peer fingerprints, or tampering with it to change pinning. | Both trust stores are keyed strictly by 32-byte `SpkiFingerprint`, with no IP/hostname/deviceId lookup path at all (Inv 3); Mac trust items live in the data-protection Keychain, app's own access group, `AfterFirstUnlockThisDeviceOnly` (E13-06); Android's is app-private Room/DataStore storage, excluded from backup by the same rule as the rest of the app (E13-02, E00-28). | Fingerprints are not secrets (public-key hashes); reading the store discloses *which* devices are paired, not a way to impersonate them — impersonation still needs the private key (row above). | `unit: trustStore_put_usesDataProtectionKeychainOwnGroup` (E13-06); `ci: mergedManifest_allowBackupTrueFixture_checkFails` (E00-28, covers the Android trust-store file's backup exclusion) | AC-09, AC-12 |
| Information disclosure (SMS / contacts at rest) | Physical access to a lost/stolen, powered-on-and-unlocked Mac reads cached SMS threads or contacts straight off disk. | GRDB SQLite files (`sms.sqlite`, `contacts.sqlite`, WAL/SHM sidecars included) are POSIX mode 0600, excluded from Time Machine backup, and use `completeUntilFirstUserAuthentication` file protection where the platform supports it (D-12, D-49; E50-09, E51-04); both stores register with `PeerDataPurgeRegistry` so unpairing a phone purges its rows, and diagnostics expose only row counts/ids, never bodies (Inv 7; E14-13). | **No application-level encryption of these databases in v1** — at-rest confidentiality against a stolen, unlocked Mac depends entirely on FileVault plus the owner's login password, an explicit owner-accepted trade-off for a single-user-Mac target (D-12, D-49). This is this chapter's principal AC-12 residual; see residual register item 14. | `unit: smsDatabaseFile_created_hasPosixMode0600`, `unit: smsDatabaseFile_created_isExcludedFromBackupTrue`, `unit: smsDatabaseFile_protectionSupported_readsBackCompleteUntilFirstUserAuth`, `unit: smsStoreDiagnostics_afterSync_containsCountsButNoBodies`, `unit: smsStore_peerUnpaired_allRowsForPeerDeleted` (E50-09); `unit: contactsDatabaseFile_created_hasPosixMode0600`, `unit: contactsStore_peerUnpaired_allRowsForPeerDeleted` (E51-04) | AC-12 |
| Information disclosure (thumbnail / icon caches, transfer temp files) | Cached photo thumbnails, per-app notification icons, or in-flight `.part` transfer files outlive the pairing they came from, or leak content for a device the owner believed unpaired. | The Mac thumbnail cache (E41-06) and icon cache (E30-06) both register with `PeerDataPurgeRegistry`, deleted on unpair; Android's transfer temp files live in app-private `noBackupFilesDir` and are deleted both on normal completion/cancel and via the Android `PeerDataPurging` registry on unpair (E14-12; E40-05). | None within the registered-purger set; a purger that throws is still recorded and retried on next launch rather than silently skipped (E14-13). | `unit: thumbnailCache_peerUnpaired_entriesForPeerDeleted` (E41-06); `unit: iconCache_peerUnpaired_iconsForPeerDeleted` (E30-06); `unit: androidReceiver_macUnpaired_retainedPartFilesDeleted` (E40-05) | AC-09, AC-12 |
| Elevation of privilege (destination files) | A received file lands somewhere other than the intended destination folder, overwrites an existing file, or is visible to other apps/queries before it is fully hash-verified. | The receiver stages to a temp/`.part` file, verifies the full SHA-256, and only then atomically moves/publishes it — MediaStore `IS_PENDING` on Android, `rename` from an `itemReplacementDirectory` on the same volume on macOS; name collisions are suffixed, never overwritten (E40-05, E40-06). | None within the tested paths. | `instrumented: mediaStorePublisher_pendingPublish_invisibleToDownloadTandemQuery`, `instrumented: mediaStorePublisher_existingSameName_originalUntouchedAndSuffixedEntryAdded` (E40-05) | AC-19 (adjacent), AC-12 |

### 10.4 Logs and crash reports

Assets: everything invariant 7 protects (secrets, message bodies, notification text, clipboard
content), plus whatever a crash report could otherwise leak.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Information disclosure (release logs, static) | A release build logs notification text, clipboard content, message bodies, SMS/contact PII, dial numbers, or protocol secrets (pairing secret, media ticket, channel binding). | Shared `tools/lint/sensitive-symbols.txt` names every sensitive field (notification text, clipboardText, smsBody/smsAddress, contactName, phoneNumber, callerNumber, inputText/inputCoordinates, pairingSecret, mediaTicket, channelBinding, fileName, displayName, deviceName, replyText); Android's `NoSensitiveReleaseLog` detekt rule fails any release-visible `Log.*`/`Timber.*` call referencing a listed symbol, and R8 strips `Log.v/d/i` entirely from release dex; the macOS equivalent check fails `os_log`/`Logger`/`print` calls referencing the same list outside `#if DEBUG`, and a non-literal value logged with `.public` privacy fails unless allowlisted (Inv 7; D-31; E00-17, E00-27). | Static, symbol-name-based checks only — a value logged through an unlisted variable name would not be caught by lint alone; the runtime canary scan below is the actual guarantee. | `ci: releaseLogLint_clipboardTextInReleaseSourceSet_detektFails`, `ci: sensitiveSymbolsList_cycle4Symbols_allPresent` (E00-17); `ci: releaseLogLint_notificationBodyViaOsLog_checkFails`, `ci: releaseLogLint_publicPrivacyOnStringValue_checkFails` (E00-27) | AC-10 |
| Information disclosure (release logs, runtime) | A real canary value (message body, phone number, contact name, notification text, clipboard text, or a secret only ever loggable in encoded form) appears in an actual captured `logcat`/unified-log session — the gap the static lint can't reach. | `tools/log-audit` scans captured logs for every supplied canary, raw and in hex/base64/base64url form, and fails on a single occurrence or an empty capture; per-domain sessions are owned by the feature epics and run before release (E15-17; D-31). | None within the canary manifest's kind coverage; a kind not yet added to the manifest for a newly enabled feature fails the tool itself rather than silently passing. | `unit: logAudit_canaryInLogcatFixture_exitsOneWithSourceAndLine`, `unit: logAudit_base64urlEncodedCanary_detected`, `unit: logAudit_manifestMissingRequiredKindForEnabledFeature_exitsNonZero` (E15-17) | AC-10 |
| Information disclosure (third-party crash / analytics SDK) | A bundled crash-reporting or analytics SDK exfiltrates notification content, stack traces with sensitive locals, or device identifiers to a third party without the owner's knowledge. | v1 ships **no third-party crash or analytics SDK** — OS-local crash reports only; a dependency on Firebase Crashlytics/Analytics, Sentry, Bugsnag, App Center, Instabug (or the Swift equivalents) fails the module-dependency-rule build on both platforms (D-31; E00-14, E00-15). | None within the denylist's coverage; a new SDK not yet on the denylist would need the list updated, same as any denylist. | `ci: dependencyDenylist_crashlyticsAdded_buildFails` (E00-14); `ci: dependencyDenylist_sentryCocoaPackageAdded_exitsNonZero` (E00-15) | AC-10, AC-18 |

### 10.5 CI and release: signing, secrets, supply chain

Assets: the release signing identities, CI secrets, the third-party dependency graph, the
"apps talk only to each other" egress guarantee.

| STRIDE | Threat | Mitigation | Residual risk | Verifying test | AC |
|---|---|---|---|---|---|
| Spoofing (unsigned / tampered release artifact) | An attacker distributes a modified or debug-signed build as if it were the real release. | Android release builds use a dedicated sideload keystore signing config (no debug keys); macOS uses local Developer ID (or ad hoc) signing; CI verifies with `apksigner verify --print-certs` / `codesign --verify --deep --strict` on every release artifact (E71-11). | None within the verification step's coverage. | `ci: releaseSigningCheck_apkSignedWithDebugKey_exitsNonZero`, `ci: releaseSigningCheck_tamperedMacApp_codesignVerifyFails` (E71-11) | AC-18 (adjacent) |
| Information disclosure (signing / CI secrets) | The Android keystore, its passwords, or the Mac Developer ID/CI keychain credentials leak through a pull-request-triggered workflow, a log, or a fork. | Signing secrets are exposed only to the release workflow on protected tags via an environment requiring a reviewer; a pull-request workflow cannot read them (E71-11); secret scanning runs on every push/PR against the full diff, with an allowlist only for known-safe test fixtures (E00-16). | None within the scan's/environment-scoping's coverage. | `ci: releaseSigningSecrets_pullRequestWorkflow_notAvailable` (E71-11); `ci: secretScan_addedThenRemovedInSamePr_stillDetected`, `ci: secretScan_allowlistedVectorFixture_notFlagged` (E00-16) | AC-18 |
| Elevation of privilege (test-only code ships) | Test doubles, fakes, or debug-only hooks (`SoftwareIdentityKeyStore`, `FakeTandemSession`, the JVM harness's pairing-payload launch hook, the companion app's package) ship inside the real release artifact and widen its attack surface or reintroduce a bypass. | Every CI release build (not only at Phase 7) scans the release APK's dex and the macOS Release Mach-O's symbols/bundle contents against a checked-in test-only-symbol list, and checks the `.app` bundle contents against an exact allowlist (Inv 2; D-30; E00-30). | None within the checked-in symbol list's coverage; a new test-only type must be added to the list or it ships undetected. | `ci: releaseApkDexScan_currentReleaseBuild_noTestOnlyClasses`, `ci: macReleaseSymbolScan_currentReleaseBuild_noTestOnlySymbols`, `ci: macReleaseBundle_unexpectedExecutableOrXctest_exitsNonZero` (E00-30) | AC-11 |
| Tampering (dependency supply chain) | A transitive dependency is swapped for a malicious version (typosquatting, compromised registry, unpinned Action) between CI runs. | Gradle `verification-metadata.xml` sha256 for every artifact plus dependency locking and no dynamic versions; SwiftPM `Package.resolved` committed, direct dependencies pinned `exact:`, CI resolution fails if the lockfile would change; GitHub Actions referenced by full commit SHA; license gate restricted to permissive licenses; every direct dependency requires a justification entry in `docs/dependencies.md` (D-32; E00-29). | None within the verification/pinning coverage; a compromised upstream release matching an already-recorded checksum (a compromise before the checksum was first pinned) is outside what checksum pinning alone can catch. | `ci: gradleDependencyVerification_tamperedArtifactChecksum_buildFails`, `ci: githubActions_unpinnedActionRef_checkFails`, `ci: licenseCheck_gplDependencyFixture_exitsNonZero` (E00-29) | AC-18 |
| Information disclosure (bundled-SDK telemetry / egress) | The QR-scanning dependency, or any other bundled SDK, phones home with usage telemetry, contradicting "the apps talk only to each other." | The QR decoder choice is gated on a zero-egress spike result: ML Kit only if 0 network connections are observed over 20 scans plus 24 h idle; otherwise the decision is zxing-cpp, which has no network code (D-32, D-43; E14-23). The whole app's egress is re-checked at release: a Mac `pktap` capture and an Android per-UID `/proc/net` sample (plus a 24 h physical-phone manual gate) must show only flows to the paired peer's address on the Tandem port (E71-14). | None within the tested session's coverage; the 24 h physical-phone manual gate is the only check that would catch a rare/delayed telemetry call, and it is a gate, not continuous monitoring. | `security: macEgressAudit_fullFeatureSession_onlyPhoneTandemPortFlows`, `instrumented: androidEgressAudit_fullSessionOnEmulator_onlyMacEndpointsForAppUid`, `manual: androidEgressAudit_physicalPhone24hCapture_onlyMacTandemPortFlows` (E71-14) | AC-18, AC-02 |

---

## 11. Residual risk register (chapter 2)

Continues the numbering of chapter 1's register (§5, items 1–13):

14. **Mac at-rest data relies entirely on FileVault/login, not app-level encryption.** SMS and
    contacts (GRDB SQLite), thumbnail and icon caches, and downloaded files carry no
    application-level encryption in v1; confidentiality against a stolen, unlocked Mac depends on
    FileVault plus the owner's login password. Explicit owner-accepted trade-off for a
    single-user-Mac target. (§10.3; D-12, D-49.) This is AC-12's principal residual.
15. **Local reachability of the Mac listener (including loopback) carries no special exemption,
    but also no special protection beyond the pin check any unauthenticated peer already faces.**
    A genuinely multi-user Mac is outside the PRD's single-user assumption; any local account
    could attempt the same connection a network attacker could, gaining nothing without a valid
    pinned key. (§10.2; D-12.)
16. **macOS screen-capture exclusion of the QR pairing window is best-effort, not an OS
    guarantee.** Cross-references chapter 1 residual item 2; this chapter is the QR window's local-
    attacker owner per E02-08's scope. (§10.2; E14-11.)
17. **Remote input can drive any on-phone UI reachable by AccessibilityService during an active,
    indicator-shown mirror session; `FLAG_SECURE` apps mirror black but still receive injected
    input.** Cross-references chapter 1 residual item 13; this chapter is its full local-surface
    owner per E02-08's scope. (Chapter 1 §4.13.)
18. **Enumerated denylists/allowlists are only as complete as the list.** Exported components,
    denied permissions, dependency licenses, test-only symbols, and crash/analytics SDK names are
    all checked against checked-in lists; a new component/permission/dependency/symbol not yet
    added to its list ships unchecked until the list is updated. Inherent to any enumerated-list
    defense, not specific to one check. (§10.1, §10.4, §10.5.)
19. **`FLAG_SECURE` is deliberately not applied on the phone.** No Tandem phone screen sets
    `FLAG_SECURE`: no secret is rendered on the phone itself (the pairing secret lives on the Mac),
    and `FLAG_SECURE` would also blank Tandem's own screens inside the Mac's mirrored view of the
    phone. Accepted residual: OS screenshots and recent-apps thumbnails of Tandem's phone screens
    can capture forwarded content, like any other non-`FLAG_SECURE` Android app. (§10.1; D-28,
    E00-28 note.)

## 12. Gaps

Threats identified while writing this chapter with **no existing backlog mitigation or test**:

1. **Mirror window is not excluded from screen capture/screen sharing.** The pairing QR window
   sets `NSWindow.sharingType = .none` and is documented as excluded from screenshots/screen
   sharing where macOS honours it (E14-11). The mirror window (`E61-07`, "Resizable mirror window
   + rotation handling"), which displays the phone's live screen content — potentially including
   message threads, notifications, or anything else visible during the mirrored session — has no
   equivalent acceptance criterion or test. A local attacker (another local account, or a screen-
   recording tool) able to see the Mac's screen could otherwise capture the mirrored phone content
   the same way the QR window's mitigation was written to prevent for the pairing secret.
   Proposed test: `unit: mirrorWindow_created_sharingTypeNoneExcludedFromCapture`. Proposed owner:
   extend `E61-07`'s acceptance/tdd list (or a new follow-up issue under the same epic) with the
   same `sharingType = .none` treatment E14-11 already gives the pairing window, with the same
   "best-effort, not an OS guarantee" caveat.

No other threat surveyed for this chapter's surfaces (§10.1–§10.5) lacked at least one existing
mitigation reference and verifying test; see the residual risk register (§11) for accepted
limits of existing mitigations, which is a distinct category from an absent mitigation.

## 13. Assumptions (chapter 2 additions)

- The Mac is a single-user machine with FileVault enabled; once local storage is reached, the
  owner's login password is the boundary (D-12, D-49). A shared/multi-user Mac is outside the
  PRD's target-user assumption (chapter 1 §6 extends the same way for network flows).
- "Local attacker on the Mac" (AC-17) is bounded to: capturing the pairing QR from the screen,
  connecting over loopback or otherwise from the same machine, or writing into the shared App
  Group queue as another process running as the same OS user — not an attacker with root or
  administrator privileges, which is out of scope for any app-level control.
- CI secrets (signing keystore, Developer ID identity) are protected by GitHub's
  environment/required-reviewer gating; a compromised CI runner itself, or a compromised GitHub
  account with administrative rights over the repository, is out of scope.
- Dependency verification and the license gate assume the checksum first recorded for a pinned
  artifact is itself trustworthy; a supply-chain compromise that occurs before that checksum is
  first pinned is not caught retroactively by pinning alone.

## 14. Abuse-case coverage index (chapter 2)

| AC | Referenced in |
|---|---|
| AC-02 | §10.2, §10.5 (adjacent) |
| AC-06 | §10.1 |
| AC-09 | §10.1, §10.3 |
| AC-10 | §10.2, §10.4 |
| AC-11 | §10.5 |
| AC-12 | §10.2, §10.3, residual item 14 |
| AC-16 | §10.1 |
| AC-17 | §10.1, §10.2, residual items 16, 19 |
| AC-18 | §10.4, §10.5 |
| AC-19 | §10.1, §10.2, §10.3 (adjacent) |

AC-12 is now fully covered across both chapters: the network-protocol half (phone unpairs while
the Mac is offline, then never dials that Mac again and a forced dial fails the pin check) is
chapter 1 §4.6; the Mac-side cached-data half (what a stolen Mac's local SMS/contacts/thumbnail
caches still expose, bounded only by FileVault) is this chapter's §10.2/§10.3. AC-18
(supply-chain/telemetry), entirely within this chapter's scope per D-33, is now covered by §10.4
(row 3) and §10.5 (rows 1, 2, 4, 5).
