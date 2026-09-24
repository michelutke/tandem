# Tandem — secure Android ↔ macOS companion (PRD, RPG format)

> Working title: **Tandem**. Rename freely; keep `TANDEM_*` identifiers consistent if you do.
> Format: Repository Planning Graph (RPG) PRD. Sections are ordered so that an agent can
> derive tasks top-down: capabilities → modules → dependencies → phases → tests.

---

<overview>

## Problem statement

Commercial Android↔Mac companion apps (reference: LinkMyMac 1.59, analyzed September 2026,
see Appendix A) move highly sensitive data across the local network: notifications, SMS,
contacts, clipboard, files, photos, the live phone screen, and remote input into the phone.
Their security is opaque, and the analyzed reference has concrete gaps: silent plaintext
fallbacks, an unencrypted screen-mirror stream, plaintext HTTP servers carrying bearer
tokens, IP-address-based trust for legacy devices, and a 32-bit manual pairing check.

Tandem is a pair of native apps (Android + macOS) that provide the same class of features
with a security model that is **encrypted and mutually authenticated on every byte, with
no fallback paths**.

## Target user

A single owner (the developer) using one Android phone with one or more Macs, on home,
office, and untrusted Wi-Fi. Distribution is personal: Android is sideloaded, macOS is
locally signed. No store policy constraints apply (this matters for SMS, call log, and
accessibility permissions).

## Goals

- Feature parity with the reference for daily use: notifications (with actions and replies),
  clipboard sync, file and photo transfer, SMS, contacts, calls control, screen mirroring
  with remote input.
- Every network path uses mutually authenticated TLS 1.3 with keys pinned at pairing.
- The Android app opens no listening sockets. The Mac exposes exactly one listening port.
- Pairing is out-of-band via QR code and cannot be downgraded.

## Non-goals (v1)

- iOS, iPad, Windows, Linux clients.
- Cloud relay, remote access over the internet, accounts.
- Phone-as-webcam, microphone bridging, call audio on the Mac (Bluetooth HFP).
- Store distribution (Play Store, Mac App Store).
- Wire compatibility with LinkMyMac.

## Success metrics

- Packet capture during a full feature session shows only TLS 1.3 records on the Tandem port;
  a planted canary string never appears in any capture (automated, see test strategy).
- Every MITM test case (wrong cert, swapped cert, replayed pairing, stale secret) fails closed.
- Notification latency Android→Mac p95 < 500 ms on the same Wi-Fi.
- Automatic reconnect < 5 s after network change or Mac wake.
- Mirroring at 1080p ≥ 30 fps with end-to-end latency < 120 ms on 5 GHz Wi-Fi.

## Clean-room rule

Tandem is designed from scratch. Do not copy code, assets, strings, or protocol structures
from LinkMyMac. The reference bundle accidentally ships two Swift source files
(`Resources/ContentView`, `Resources/ScreenMirrorView.BACKUP`); they are out of bounds.
Appendix A records *observations* only, as a list of mistakes to avoid.

</overview>

---

<functional-decomposition>

Capabilities are grouped by domain. Each feature lists inputs, outputs, and behavior.
IDs (`F-x.y`) are stable and referenced by the roadmap and tests.

## Capability 1: Identity and trust

### F-1.1 Device identity
- **Description:** Each device owns a long-term P-256 key pair and a self-signed X.509
  certificate used as its TLS identity.
- **Inputs:** First launch.
- **Outputs:** Identity stored in Android Keystore / macOS Keychain; SPKI SHA-256 fingerprint.
- **Behavior:** Android generates the key in AndroidKeyStore (StrongBox if available, else TEE),
  non-exportable. macOS generates the key with CryptoKit/Security and stores it in the
  Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The certificate carries
  no meaningful identity; only the SPKI fingerprint is trusted.

### F-1.2 Trust store
- **Description:** Persistent list of paired peers keyed by SPKI fingerprint.
- **Inputs:** Successful pairing, unpair action, remote revoke message.
- **Outputs:** Peer records `{deviceId, displayName, spkiSha256, pairedAt, lastSeen, capabilities}`.
- **Behavior:** Trust is bound to the fingerprint only, never to an IP, hostname, or device ID.
  Unpair deletes the record on both sides when reachable and immediately on the local side.

### F-1.3 Key rotation
- **Description:** Replace a device identity without re-pairing.
- **Inputs:** User action or scheduled rotation.
- **Outputs:** New fingerprint accepted by all peers.
- **Behavior:** Over an existing authenticated session, the device sends
  `KeyRotation{newSpki, sigOldKey(newSpki||nonce)}`. Peers pin the new key and keep the old one
  for one grace session. No rotation over unauthenticated channels.

## Capability 2: Pairing

### F-2.1 QR pairing (only v1 pairing method)
- **Description:** Mac displays a QR code; phone scans it and establishes mutual trust.
- **Inputs:** QR payload `tandem://pair?v=1&fp=<b64url SPKI-SHA256 Mac>&s=<b64url 128-bit secret>&a=<addr1,addr2>&p=<port>&n=<Mac name>`.
- **Outputs:** Both sides store each other's fingerprint.
- **Behavior:**
  1. Mac generates a fresh secret per pairing window (expiry 120 s, max 3 attempts, single use).
  2. Phone connects over TLS 1.3, pinning the Mac's fingerprint from the QR code, and presents
     its own certificate.
  3. Phone sends `PairRequest{deviceInfo, proof}` where
     `proof = HMAC-SHA256(secret, "tandem-pair-v1" || macSpki || phoneSpki)`.
  4. Mac verifies the proof in constant time against the phone certificate it actually saw in
     the handshake, shows a confirmation dialog ("Pair Pixel 9?"), and on accept replies
     `PairAccepted`. It then pins the phone fingerprint.
  5. Any failure closes the connection and burns an attempt.

### F-2.2 Manual pairing (deferred, v2+)
- **Description:** Pairing without a camera.
- **Behavior:** Only allowed with a commitment-based short authentication string (hash
  commitment to nonces before reveal, ≥ 6 digits compared on both screens), never with a
  fingerprint prefix check. Must go through a separate ADR before implementation.

### F-2.3 Unpair and revoke
- **Behavior:** Local unpair deletes trust immediately and sends `Revoke` if connected. The
  Mac UI lists paired phones with last-seen time and a revoke button.

## Capability 3: Secure transport

### F-3.1 Control connection
- **Description:** One long-lived mutually authenticated TLS 1.3 connection per peer pair,
  carrying all non-media channels.
- **Inputs:** Trusted peer and reachable address.
- **Outputs:** Multiplexed framed stream.
- **Behavior:** The phone always dials; the Mac always listens on a single port. TLS 1.3 only,
  no session resumption, no 0-RTT. Both sides verify the peer SPKI fingerprint against the trust
  store inside the handshake verify callback; an unknown key fails the handshake, except
  during an open pairing window.

### F-3.2 Framing and multiplexing
- **Behavior:** Frame = `u32 length (big-endian) | protobuf Envelope`. The envelope carries
  `channel`, `seq`, `ack`, and a `oneof` payload. Max frame 1 MiB. Channels: `CONTROL`,
  `NOTIFY`, `CLIPBOARD`, `FILES`, `SMS`, `CONTACTS`, `CALLS`, `INPUT`, `STATUS`. Credit-based
  flow control per channel so a large file transfer cannot starve notifications.

### F-3.3 Media connection
- **Description:** A second mTLS connection for high-bandwidth, latency-sensitive streams
  (screen mirror video). It avoids head-of-line blocking on the control connection.
- **Behavior:** Same identities and pins as F-3.1. Opened on demand. It is bound to the control
  session with a `mediaTicket` (random 256-bit value issued over the control channel,
  single use, 30 s expiry). The media connection is still full mTLS; the ticket only binds it
  to a session.

### F-3.4 Liveness and reconnect
- **Behavior:** Heartbeat every 15 s on the control channel; dead after 3 misses. Phone
  reconnect strategy: last working address → Bonjour-resolved addresses → addresses from
  pairing, with exponential backoff (1 s → 30 s cap), reset on network change events.

### F-3.5 Discovery
- **Behavior:** Mac advertises `_tandem._tcp` via Bonjour. The TXT record contains only
  `v=1` and a rotating 8-byte identifier `HMAC(macSpki, dayIndex)`, which paired phones can
  recognize and strangers cannot track. Discovery data is a hint; it never supplies keys or
  bypasses verification.

## Capability 4: Connection lifecycle and status

### F-4.1 Android background service
- **Behavior:** Foreground service (`connectedDevice` type) holding the control connection.
  Uses `CompanionDeviceManager` presence observation where available to restart after kills.
  Onboarding asks for unrestricted battery.

### F-4.2 Mac menu bar agent
- **Behavior:** Menu bar extra showing connection state, battery, and quick actions
  (send file, clipboard push, find phone, mirror). Launch at login via `SMAppService`.

### F-4.3 Device status
- **Behavior:** Phone publishes battery level, charging state, network type, and signal level
  on the `STATUS` channel on change and at most every 60 s.

### F-4.4 Find my phone
- **Behavior:** Mac sends `Ring`; phone plays an alarm at max volume, overriding DND, until
  dismissed.

## Capability 5: Notifications

### F-5.1 Mirror notifications Android → Mac
- **Inputs:** `NotificationListenerService` posts and removals.
- **Outputs:** Mac `UNUserNotification` with app name, icon, title, text, and actions.
- **Behavior:** Per-app allow/deny list (default: all except Tandem itself and system noise).
  App icons are sent once per app and version, then cached by package name on the Mac.
  Group conversation notifications (MessagingStyle) keep sender names.

### F-5.2 Actions and inline replies
- **Behavior:** Notification actions and `RemoteInput` replies are forwarded as
  `NotificationAction{key, actionIndex, replyText?}`. The phone fires the PendingIntent with
  the RemoteInput bundle.

### F-5.3 Dismiss sync
- **Behavior:** Dismissing on either side dismisses on the other (`cancelNotification(key)` on
  Android, `removeDeliveredNotifications` on the Mac).

### F-5.4 Sensitive-content handling
- **Behavior:** Optional "hide content on Mac lock screen." Notifications marked
  `VISIBILITY_SECRET` show only the app name unless the user opts in.

## Capability 6: Clipboard

### F-6.1 Mac → Android
- **Behavior:** The Mac polls `NSPasteboard.changeCount` (250 ms). Text changes are sent;
  the phone writes the clip. Concealed pasteboard types (password managers,
  `org.nspasteboard.ConcealedType`) are skipped.

### F-6.2 Android → Mac
- **Behavior:** Android 10+ blocks background clipboard reads. v1 options: share sheet
  target, Quick Settings tile, text-selection "Send to Mac" (`PROCESS_TEXT`), and the
  foreground app. Accessibility-based automatic capture is a documented opt-in (ADR required),
  off by default.

### F-6.3 Loop and size guards
- **Behavior:** Origin tag plus content hash prevent echo loops. Max 1 MiB of text; images are
  out of scope for v1 (use file transfer).

## Capability 7: Files and photos

### F-7.1 Send file
- **Behavior:** Either direction. `FileOffer{id, name, size, mime, sha256}` → accept or auto-accept
  from a trusted peer → chunked transfer (256 KiB) with per-chunk sequence numbers → final
  whole-file SHA-256 verification. Resumable by offset after a disconnect. The receiver writes
  to a temp file and moves it atomically on success.

### F-7.2 Mac integration
- **Behavior:** Drag and drop onto the menu bar window, Share extension ("Send to phone"),
  Finder Services. Received files go to `~/Downloads/Tandem/`.

### F-7.3 Android integration
- **Behavior:** Share sheet target, in-app picker (SAF). Received files go to
  `Download/Tandem/` via MediaStore.

### F-7.4 Photo browser
- **Behavior:** The Mac requests paged MediaStore listings
  (`PhotoPage{cursor, limit}`), thumbnails (`Thumb{id, maxPx}`), and originals. The Mac caches
  thumbnails in an LRU disk cache.

### F-7.5 Storage browser (v2)
- **Behavior:** Browse phone storage from the Mac. Later exposed as a File Provider extension in
  Finder. No WebDAV and no plaintext HTTP server.

## Capability 8: Messaging, contacts, calls

### F-8.1 SMS read and sync
- **Behavior:** Read threads and messages from the Telephony provider (`READ_SMS`); incremental
  sync by `_id` watermark; `ContentObserver` for new messages. MMS (images) in v2.

### F-8.2 SMS send
- **Behavior:** `SmsManager.sendMultipartTextMessage` with delivery status reported back.
  Multi-SIM: choose a subscription.

### F-8.3 Contacts
- **Behavior:** Read-only sync of name, phone numbers, emails, and photo thumbnail. Used by the
  SMS and call UI.

### F-8.4 Calls control
- **Behavior:** Incoming call notification on the Mac with caller ID; answer, decline, and hang up
  via `TelecomManager` (`ANSWER_PHONE_CALLS`); place calls with `ACTION_CALL` from the Mac.
  Audio stays on the phone. Call log view in v2.

## Capability 9: Screen mirroring and remote input

### F-9.1 Capture and encode (Android)
- **Behavior:** `MediaProjection` (consent per session, as Android requires) →
  `VirtualDisplay` → `MediaCodec` H.264 (HEVC if both sides support it), CBR, low-latency
  profile, keyframe on request. Frames are sent over the media connection (F-3.3) as
  `MediaFrame{pts, flags, data}`.

### F-9.2 Decode and render (macOS)
- **Behavior:** `VTDecompressionSession` → `AVSampleBufferDisplayLayer` in a resizable window;
  request a keyframe on decoder error; rotation handling.

### F-9.3 Remote input
- **Behavior:** Mac mouse and keyboard events are mapped to phone coordinates and sent on the
  `INPUT` channel. The phone injects them via `AccessibilityService.dispatchGesture` (taps,
  swipes, scroll) and `performGlobalAction` (back, home, recents). Text is inserted with
  `ACTION_SET_TEXT` on the focused node.
- **Security:** Input is only accepted while a mirror session the user started on the phone is
  active, with a persistent on-phone indicator. Accessibility is opt-in and explained.

### F-9.4 Alternative path (ADR-decided)
- **Behavior:** Optional "advanced mirroring" through ADB wireless debugging and scrcpy-server
  (Apache 2.0), which gives better input injection and does not need accessibility. It requires
  developer mode. Decide in ADR-006 whether to support it in v1 or v2.

## Capability 10: Extras (v2+)

- **F-10.1 Media control:** now-playing info and transport controls from the Mac (`MediaSessionManager`).
- **F-10.2 Focus/DND sync:** the Mac Focus state toggles phone DND (`NotificationManager.setInterruptionFilter`).
- **F-10.3 USB transport:** the same framed mTLS protocol over a USB link (AOA or ADB forward), for speed and no-Wi-Fi scenarios.
- **F-10.4 Multi-Mac:** one phone connected to several paired Macs at the same time.

</functional-decomposition>

---

<structural-decomposition>

## Repository layout (monorepo)

```
tandem/
├── CLAUDE.md                     # agent conventions, commands, security invariants
├── docs/
│   ├── PRD.md                    # this file
│   ├── protocol/SPEC.md          # normative wire protocol (RFC 2119 language)
│   ├── threat-model.md           # STRIDE per data flow
│   └── adr/                      # ADR-001 … numbered decisions
├── protocol/
│   ├── proto/tandem/v1/*.proto   # single source of truth for messages
│   ├── vectors/                  # cross-platform test vectors (JSON + binary)
│   └── buf.yaml                  # lint + breaking-change checks
├── android/
│   ├── app/                      # UI (Compose), onboarding, settings, DI wiring
│   ├── core/protocol/            # generated protobuf-kotlin-lite + framing codec
│   ├── core/crypto/              # Keystore identity, fingerprints, HMAC, pinning TrustManager
│   ├── core/transport/           # TLS client, multiplexer, flow control, reconnect
│   ├── core/pairing/             # QR parsing, pairing state machine
│   ├── core/storage/             # trust store, settings (DataStore), caches
│   ├── feature/notifications/
│   ├── feature/clipboard/
│   ├── feature/files/            # includes photos
│   ├── feature/messaging/        # SMS + contacts
│   ├── feature/calls/
│   ├── feature/mirror/           # MediaProjection + MediaCodec
│   └── feature/input/            # AccessibilityService
├── macos/
│   ├── Tandem.xcodeproj
│   ├── TandemApp/                # SwiftUI + AppKit menu bar app target
│   ├── TandemShare/              # Share extension target
│   └── Packages/
│       ├── TandemProtocol/       # swift-protobuf generated + framing codec
│       ├── TandemCrypto/         # identity, swift-certificates, fingerprints, HMAC
│       ├── TandemTransport/      # NWListener TLS server, multiplexer, flow control
│       ├── TandemPairing/        # QR generation, pairing window state machine
│       ├── TandemStore/          # trust store, settings, caches
│       └── Feature*/             # Notifications, Clipboard, Files, Messaging, Calls, Mirror
└── tools/
    ├── conformance/              # runs vectors against both codecs
    ├── pcap-audit/               # tshark-based "no plaintext" checker
    ├── mitm-lab/                 # scripted MITM scenarios (wrong or swapped certs)
    └── fuzz/                     # Jazzer (Kotlin) + libFuzzer (Swift) frame parser targets
```

## Module to capability mapping

| Module (Android / macOS) | Capabilities |
|---|---|
| `core/crypto` / `TandemCrypto` | F-1.1, F-1.3, pinning for F-3.1 and F-3.3 |
| `core/storage` / `TandemStore` | F-1.2, settings, caches |
| `core/pairing` / `TandemPairing` | F-2.x |
| `core/protocol` / `TandemProtocol` | F-3.2 codec |
| `core/transport` / `TandemTransport` | F-3.1, F-3.3, F-3.4, F-3.5 |
| `app` / `TandemApp` | F-4.x, UI for everything |
| `feature/*` / `Feature*` | F-5 … F-10 |

## Module rules

- Features depend on `core/*` and never on each other.
- Only `core/transport` touches sockets. Only `core/crypto` touches key material.
- Generated protocol code is never edited by hand; regenerate from `.proto`.

</structural-decomposition>

---

<dependency-graph>

## Foundation layer (no dependencies)

- **P0-A** Protocol schema (`.proto`) + `SPEC.md` + test vectors.
- **P0-B** Threat model + ADR-001 … ADR-006 (listed under architecture).
- **P0-C** Repo scaffolding, CI (Android: Gradle, ktlint, detekt; macOS: xcodebuild, SwiftLint; buf lint).

## Layer 1: primitives

- `core/protocol`, `TandemProtocol` ← P0-A
- `core/crypto`, `TandemCrypto` ← P0-A (fingerprint and HMAC vectors)
- `core/storage`, `TandemStore` ← `crypto`

## Layer 2: secure channel

- `core/transport`, `TandemTransport` ← `protocol`, `crypto`, `storage`
- `core/pairing`, `TandemPairing` ← `transport`, `crypto`, `storage`

## Layer 3: lifecycle

- Android foreground service + reconnect, Mac menu bar agent + listener ← `transport`, `pairing`
- Discovery (F-3.5) ← `transport`

## Layer 4: features (parallelizable)

- Status and find phone (F-4.3, F-4.4) ← Layer 3
- Notifications (F-5) ← Layer 3
- Clipboard (F-6) ← Layer 3
- Files and photos (F-7) ← Layer 3 + flow control complete
- Messaging and contacts (F-8.1–8.3) ← Layer 3
- Calls (F-8.4) ← Contacts

## Layer 5: media

- Media connection (F-3.3) ← Layer 3
- Mirror (F-9.1, F-9.2) ← media connection
- Remote input (F-9.3) ← mirror

## Layer 6: extras

- F-10.x ← respective features; USB transport ← transport abstraction proven over TCP

</dependency-graph>

---

<implementation-roadmap>

Each phase has entry criteria, tasks, and exit criteria. Do not start a phase until the
previous phase's exit criteria pass in CI.

## Phase 0 — Foundations

**Entry:** Empty repo.
**Tasks:**
1. Scaffold the monorepo, `CLAUDE.md`, CI pipelines for both platforms.
2. Write `docs/protocol/SPEC.md` v1: handshake, pairing, framing, channels, errors, versioning.
3. Write `protocol/proto/tandem/v1/` for envelope, pairing, control, and status messages.
4. Produce test vectors: fingerprint computation, pairing proof HMAC, frame encoding (valid and
   invalid), Bonjour rotating ID.
5. Write the threat model and ADR-001 … ADR-006.
**Exit:** `buf lint` passes; vectors reviewed; ADRs accepted.

## Phase 1 — Identity, pairing, secure transport

**Entry:** Phase 0 done.
**Tasks:**
1. Android: Keystore P-256 identity + self-signed cert; SPKI fingerprint (vector-tested).
2. macOS: Keychain identity + self-signed cert via `swift-certificates`; SPKI fingerprint.
3. macOS: `NWListener` with TLS 1.3-only options, local identity, client-cert required, verify
   block against the trust store and pairing window.
4. Android: `SSLSocket` (platform Conscrypt) with a custom `X509TrustManager` (pin check) and
   `X509KeyManager` (Keystore key); TLS 1.3 only.
5. Framing codec + multiplexer + flow control on both sides; conformance against vectors.
6. Pairing state machines (F-2.1) with the QR generator (Mac) and scanner (Android, CameraX + ML Kit).
7. Trust store, unpair, revoke.
**Exit:**
- A phone pairs with a Mac via QR and reconnects after restarting both apps.
- `pcap-audit` shows only TLS 1.3 on the Tandem port and no canary strings.
- All `mitm-lab` scenarios fail closed: unknown client cert, wrong server cert, replayed
  `PairRequest`, expired secret, 4th attempt, proof computed for a different phone key.
- `nmap` against the phone shows no Tandem listening ports.

## Phase 2 — Lifecycle and reliability

**Tasks:** Foreground service, CompanionDeviceManager presence, battery onboarding; heartbeat;
reconnect strategy; Bonjour advertise and browse with the rotating ID; Mac menu bar agent,
launch at login; connection state UI on both sides; status channel (F-4.3); find phone (F-4.4).
**Exit:** Survives Mac sleep/wake, Wi-Fi switch, phone Doze overnight; reconnect < 5 s p95.

## Phase 3 — Notifications and clipboard

**Tasks:** F-5.1–5.4, F-6.1–6.3, per-app filter UI, icon cache.
**Exit:** Reply to a WhatsApp and a Signal notification from the Mac; dismiss sync both ways;
no clipboard echo loops; concealed pasteboard items never leave the Mac.

## Phase 4 — Files and photos

**Tasks:** F-7.1–7.4, Share extension (macOS), share target (Android), resume after disconnect.
**Exit:** Transfer 4 GB both ways with a forced disconnect midway; SHA-256 matches; transfer does
not delay notifications (flow-control test).

## Phase 5 — Messaging, contacts, calls

**Tasks:** F-8.1–8.4, conversation UI on the Mac, multi-SIM handling.
**Exit:** Send and receive SMS from the Mac; incoming call shows on the Mac within 1 s; answer
and hang up from the Mac work.

## Phase 6 — Mirroring and remote input

**Tasks:** Media connection with ticket binding (F-3.3); F-9.1–9.3; decide ADR-006
(scrcpy path) and implement if accepted.
**Exit:** Mirroring meets the success metrics; `pcap-audit` passes during mirroring; input is
rejected when no user-started session exists.

## Phase 7 — Extras and hardening

**Tasks:** F-10.x as prioritized; key rotation (F-1.3); fuzzing campaigns; external review of
`SPEC.md`; manual pairing ADR (F-2.2) if still wanted.

</implementation-roadmap>

---

<test-strategy>

## Test pyramid

- **Unit tests:** codecs, state machines (pairing, reconnect, flow control), crypto helpers.
  Android: JUnit5 + Turbine for Flows. macOS: Swift Testing.
- **Conformance tests:** `protocol/vectors/` is executed by both platforms in CI. Any vector
  failure blocks merge.
- **Integration tests:** a JVM test client (reusing `core/*` modules) runs against the real Mac
  server on a macOS CI runner, and a Swift test client runs against Android transport code via
  Robolectric/JVM where possible.
- **Device tests:** instrumented tests for Keystore, NotificationListener, MediaCodec on a
  physical device (manual gate per phase).

## Security tests (required per phase from Phase 1)

| Test | Tool | Pass condition |
|---|---|---|
| No plaintext on the wire | `tools/pcap-audit` (tshark) | Only TLS 1.3 records on the Tandem port; canary strings absent from the whole capture |
| No phone listeners | `nmap -p- <phone>` | No Tandem ports open |
| Wrong or swapped certs | `tools/mitm-lab` | Handshake fails; no application data sent |
| Pairing replay and brute force | `tools/mitm-lab` | Replays rejected; 4th attempt rejected; secret expires |
| Downgrade attempts | `openssl s_client -tls1_2` and similar | Rejected |
| Parser robustness | Jazzer / libFuzzer on frame and envelope decoding | No crashes over 24 h per target |
| Session binding | Media connection without or with a reused `mediaTicket` | Rejected |
| Input authorization | `INPUT` frames with no active user-started session | Ignored and logged |

## Canary procedure

Before each capture, sync the clipboard text `TANDEM-CANARY-<random>`, send a file containing
it, trigger a notification with it, and display it on the mirrored screen. `pcap-audit` fails
if the bytes appear anywhere in the capture.

</test-strategy>

---

<architecture>

## Technology stack

**Android**
- Kotlin, Coroutines/Flow, Jetpack Compose, Hilt, DataStore.
- `minSdk 29` (Android 10), `targetSdk` latest.
- Platform `SSLSocket` (Conscrypt) with custom `X509TrustManager` / `X509KeyManager`;
  AndroidKeyStore P-256 (StrongBox preferred).
- `protobuf-kotlin-lite` generated from `protocol/proto`.
- CameraX + ML Kit barcode scanning for QR.
- MediaProjection + MediaCodec for mirroring; AccessibilityService for input.

**macOS**
- Swift 6 (strict concurrency), SwiftUI + AppKit (`MenuBarExtra`, `NSWindow` for mirror).
- `minimum macOS 15`.
- Network.framework (`NWListener`, `NWProtocolTLS.Options`, `sec_protocol_options_*`) for mTLS.
- Apple `swift-certificates` + `swift-crypto` for self-signed certificate generation.
- `swift-protobuf`; VideoToolbox + AVFoundation for decoding; UserNotifications.
- App Sandbox with `network.server` and `network.client` entitlements.

## Security invariants (copy into CLAUDE.md)

1. No code path may send application data over a socket that has not completed mTLS with a pinned peer.
2. No plaintext listener, no HTTP server, no WebDAV, no "legacy" or "fallback" mode — ever.
3. Trust is bound to SPKI fingerprints only; IP addresses and device IDs are never trust anchors.
4. The Android app opens no listening sockets.
5. Pin mismatch, unknown peer, or protocol version mismatch fails closed with a visible error.
6. Secrets are compared in constant time; pairing secrets are single-use and expire.
7. Logs never contain secrets, message bodies, notification text, or clipboard content in release builds.
8. Remote input is accepted only during a user-started mirror session with an on-phone indicator.

## Architecture decision records to write in Phase 0

- **ADR-001:** Native Swift + native Kotlin with a shared Protobuf schema (no KMP/CMP).
  Rationale: platform APIs dominate; TLS must be platform-specific anyway; Swift↔Kotlin/Native
  interop cost outweighs the small shared surface.
- **ADR-002:** Phone as TLS client, Mac as the only server; single listening port.
- **ADR-003:** mTLS 1.3 with self-signed certs and SPKI pinning (vs. Noise protocol). Rationale:
  first-class platform support on both sides, audited implementations.
- **ADR-004:** QR-only pairing for v1; manual pairing only with a commitment-based SAS.
- **ADR-005:** Two connections (control + media) vs. one multiplexed connection.
- **ADR-006:** Mirroring via MediaProjection + Accessibility vs. ADB wireless + scrcpy-server.

## Data flow summary

```
Android (TLS client, no listeners)                 macOS (single mTLS listener)
┌──────────────────────────────┐   control mTLS   ┌──────────────────────────────┐
│ NotificationListener ─┐      │ ───────────────▶ │ ┌─ UNUserNotificationCenter  │
│ Clipboard / Share ────┤      │                  │ ├─ NSPasteboard              │
│ Files / MediaStore ───┼─ Mux │ ◀─────────────── │ Mux ─ Files / Photo cache    │
│ SMS / Contacts ───────┤      │                  │ ├─ Messages UI               │
│ Telecom ──────────────┘      │                  │ └─ Calls UI                  │
│ MediaCodec ─────────────────▶│   media mTLS     │ VideoToolbox ─ Mirror window │
│ AccessibilityService ◀───────│ ◀─────────────── │ Input capture                │
└──────────────────────────────┘                  └──────────────────────────────┘
```

</architecture>

---

<risks>

| Risk | Impact | Mitigation |
|---|---|---|
| Android kills the background service (OEM battery policies) | Missed notifications, slow reconnect | Foreground service, CompanionDeviceManager presence, onboarding for unrestricted battery, reconnect on `CONNECTIVITY_CHANGE` |
| Keystore-backed keys with `SSLSocket` client auth behave differently across OEMs | Handshake failures | Early device matrix test in Phase 1; fallback to TEE if StrongBox fails (never to exportable keys) |
| Network.framework TLS client-cert and verify-block edge cases | Blocked Phase 1 | Spike in Phase 0; fallback option: swift-nio-ssl (BoringSSL) |
| Android background clipboard restrictions | Weaker Android→Mac clipboard UX | Tile, share, `PROCESS_TEXT`; accessibility capture only as documented opt-in |
| MediaProjection consent per session (Android 14+) | Mirroring requires phone interaction | Accept; optional ADB/scrcpy path (ADR-006) |
| Accessibility service is a high-privilege surface | Abuse if the transport is compromised | Invariant 8; input only in user-started sessions; minimal accessibility config |
| Wi-Fi client isolation on guest or office networks | No connectivity | Detect and explain; USB transport (F-10.3); phone hotspot |
| Scope creep (webcam, mic, call audio) | Delays | Non-goals list; Phase 7 only |
| Protocol drift between platforms | Subtle bugs | Protobuf single source, `buf breaking`, conformance vectors in CI |

</risks>

---

<appendix>

## Appendix A — reference analysis: LinkMyMac 1.59 (observations only)

Static analysis of the Android APK (`com.kdg.beam_android` 1.59) and the Mac bundle
(`com.linkmymac.mac` 1.59). No runtime testing. These are failure patterns to avoid, not
designs to reuse.

**What it does well**
- Pins the Mac TLS key fingerprint delivered via QR (TLS 1.3/1.2) for the control channel and HTTPS transfers.
- Session tokens with timestamp and nonce on the phone's file server; HMAC-SHA256 auth on auxiliary streams.
- The Mac rejects plaintext Wi-Fi control connections while TLS control is enabled; auxiliary
  listeners (mirror frames, mic, playback, webcam) reject unauthenticated connections.
- No third-party analytics SDKs found in the Mac binary.

**Gaps (each maps to a Tandem invariant)**
- Silent plaintext fallback when no fingerprint is stored: control on port 53100, file
  transfer over `http://…:53102` → invariant 2.
- Fingerprint can be updated via a message on an unauthenticated channel → invariant 1.
- Screen mirroring to TCP 53104 is authenticated but not encrypted; mic, playback, and webcam
  streams appear to follow the same pattern → invariant 1.
- The phone runs a plaintext HTTP server on 53120 next to HTTPS on 53122, with bearer tokens in
  headers → invariants 2 and 4.
- The Mac accepts a "legacy Android identity from pinned paired address" → invariant 3.
- Manual pairing compares only a 32-bit fingerprint prefix → ADR-004.
- `cleartextTrafficPermitted="true"` app-wide on Android; ATS `NSAllowsLocalNetworking` on the
  Mac; plain HTTP servers (Swifter, "Screen Mirror HTTP server") and WebDAV mounting on the Mac → invariant 2.
- The bundle ships leftover Swift source files in `Resources/` (out of bounds for this project).

**Feature inventory observed (scope reference)**
Notifications with actions and replies, SMS, contacts, calls with optional Mac audio over
Bluetooth, clipboard, files, photo browser, storage mounting (WebDAV), screen mirroring and
control, "advanced mirroring" via bundled scrcpy-server 4.0 and a native ADB client over
wireless debugging, phone as webcam (camera system extension), microphone, Focus/DND sync,
web wrappers for WhatsApp, Telegram, and Google Messages, share extension, phone-to-phone
LinkMyDrop (ECDH + AES-GCM).

## Appendix B — glossary

- **SPKI fingerprint:** SHA-256 over the DER-encoded SubjectPublicKeyInfo of a certificate.
- **mTLS:** TLS where both sides present and verify certificates.
- **Pairing window:** the time-limited state on the Mac in which an unknown client certificate
  may connect, only to complete F-2.1.
- **Media ticket:** single-use token that binds a media connection to a control session.

## Appendix C — open questions

1. Secure Enclave for the Mac TLS key: can a Secure-Enclave-backed key be used as a
   Network.framework `sec_identity` reliably? Spike in Phase 0; default is a Keychain key.
2. Multi-Mac (F-10.4): one control connection per Mac, or a phone-side broker?
3. Should the Mac also be able to initiate reconnects (for example, via a phone-side
   Bluetooth LE advertisement hint)? This must not add a phone listening socket.
4. MMS and RCS: RCS is not accessible to third-party apps; confirm scope with the actual daily SMS mix.

## Appendix D — suggested CLAUDE.md skeleton

```markdown
# Tandem — agent guide
- Read docs/PRD.md and docs/protocol/SPEC.md before any change to transport, pairing, or crypto.
- Security invariants (docs/PRD.md › architecture) are non-negotiable; if a task seems to
  require breaking one, stop and ask.
- Never edit generated protocol code; change protocol/proto and regenerate.
- Commands:
  - Android: ./gradlew :app:assembleDebug test detekt ktlintCheck
  - macOS:   xcodebuild -scheme Tandem test ; swiftlint
  - Protocol: buf lint && buf breaking --against '.git#branch=main'
  - Conformance: tools/conformance/run.sh
- Every PR touching core/* must include or update tests and pass tools/pcap-audit locally.
```

</appendix>
