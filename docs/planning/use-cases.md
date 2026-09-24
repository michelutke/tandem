# Tandem — use cases and abuse cases

Actors: **Owner** (single user), **Phone** (Tandem Android app), **Mac** (Tandem macOS agent),
**Attacker** (anyone else on the local network or with brief physical access).

Each use case lists its trigger, main flow, alternate/failure flows, and acceptance checks.
Acceptance checks are written so they can become tests. PRD feature IDs (`F-x.y`) in brackets.

---

## Setup and trust

### UC-01 Mac first-run setup [F-1.1, F-4.2]
- **Trigger:** Owner launches Tandem.app for the first time.
- **Main flow:** Mac generates a P-256 identity in the Keychain → self-signed cert → menu bar
  icon appears (state "Not paired") → Owner is offered "Launch at login" → Owner opens "Pair phone".
- **Alternate:** Keychain unavailable / denied → visible error, no identity, no listener.
  Existing identity found → reused, fingerprint unchanged.
- **Acceptance:**
  - [ ] Identity key is `…AfterFirstUnlockThisDeviceOnly`, non-exportable where supported.
  - [ ] Relaunch keeps the same SPKI fingerprint.
  - [ ] No listening socket exists until an identity exists.
  - [ ] Launch-at-login toggle reflects `SMAppService` status.

### UC-02 Phone onboarding [F-1.1, F-4.1]
- **Trigger:** Owner installs and opens the Android app.
- **Main flow:** Phone generates Keystore identity (StrongBox → TEE) → onboarding explains each
  permission (notifications listener, post notifications, battery unrestricted, camera for QR;
  later features ask lazily) → "Scan Mac QR".
- **Alternate:** StrongBox unavailable → TEE, logged (no key material). Owner denies optional
  permissions → feature shows "disabled, tap to enable", core pairing still works.
- **Acceptance:**
  - [ ] Key is hardware-backed and non-exportable (`KeyInfo.isInsideSecureHardware`).
  - [ ] App never opens a listening socket (nmap clean).
  - [ ] Every permission screen has a skip path, except camera during scanning.

### UC-03 Pair phone with Mac via QR [F-2.1]
- **Trigger:** Owner clicks "Pair phone" on the Mac.
- **Main flow:**
  1. Mac opens a pairing window (fresh 128-bit secret, 120 s, 3 attempts) and shows QR + countdown.
  2. Phone scans QR, validates payload, dials an address from the QR, pins Mac SPKI from `fp`.
  3. Phone presents its cert; Mac accepts the unknown cert only because a window is open.
  4. Phone sends `PairRequest{deviceInfo, proof}`; Mac verifies proof (constant time) against the
     phone cert seen in the handshake.
  5. Mac asks "Pair <phone name>?" → Owner accepts → `PairAccepted` → both sides store the peer.
  6. Window closes; secret is destroyed; control session continues as normal.
- **Alternate:** Owner rejects on Mac → `PairRejected`, connection closed, attempt burned.
  QR expired → phone shows "QR expired, refresh on Mac". Mac unreachable on every address →
  phone shows network hint (client isolation, different Wi-Fi).
- **Acceptance:**
  - [ ] End-to-end pairing completes in < 10 s after scan on same Wi-Fi.
  - [ ] Both trust stores contain exactly one new record with matching fingerprints.
  - [ ] The same QR cannot be used twice.
  - [ ] Pairing survives restart of both apps (reconnect without re-pair).

### UC-07 Unpair / revoke a device [F-2.3, F-1.2]
- **Trigger:** Owner taps "Unpair" on phone or "Revoke" on Mac.
- **Main flow:** Local record deleted immediately → `Revoke` sent if connected → peer deletes
  its record → connection closed.
- **Alternate:** Peer offline → local deletion only; next connection attempt fails handshake
  (unknown key) with a visible "This device is no longer paired" message.
- **Acceptance:**
  - [ ] After revoke, the removed peer's handshake fails (mitm-lab-style test).
  - [ ] Mac list shows last-seen time for each paired phone.

### UC-24 Rotate device key [F-1.3]
- **Trigger:** Owner taps "Rotate key", or scheduled rotation fires.
- **Main flow:** Over an authenticated session, device sends `KeyRotation{newSpki, sig}` → peer
  verifies signature with the old pinned key → pins new key, keeps old for one grace session →
  next session uses new key.
- **Alternate:** Peer offline → rotation queued, old key kept. Signature invalid → rejected, logged.
- **Acceptance:**
  - [ ] Rotation message on an unauthenticated / pairing-window connection is rejected.
  - [ ] Old key stops working after the grace session.

---

## Connectivity and status

### UC-04 Reconnect automatically [F-3.4, F-3.5, F-4.1]
- **Trigger:** Wi-Fi switch, Mac wake, phone reboot, app kill by OEM, Doze exit.
- **Main flow:** Phone detects network change → tries last working address → Bonjour-resolved
  addresses (rotating ID matched) → pairing addresses, backoff 1 s → 30 s, reset on network change.
- **Alternate:** Mac asleep → backoff continues; Mac wake → Mac restarts listener; phone
  reconnects on next attempt. Wrong peer answers on an address (IP reused) → pin mismatch →
  fail closed, try next address.
- **Acceptance:**
  - [ ] Reconnect < 5 s p95 after network change or Mac wake.
  - [ ] Survives phone Doze overnight.
  - [ ] A host on a previously used IP with a different key never receives application data.

### UC-05 View connection and phone status on Mac [F-4.2, F-4.3]
- **Main flow:** Menu bar shows connected/connecting/disconnected, battery %, charging,
  network type, signal. Updates on change, at most every 60 s otherwise.
- **Acceptance:**
  - [ ] Status change visible on Mac within 2 s.
  - [ ] Errors (pin mismatch, version mismatch) visible in menu, not only in logs.

### UC-06 Find my phone [F-4.4]
- **Main flow:** Owner clicks "Find phone" → `Ring` → phone plays alarm at max volume overriding
  DND until dismissed on phone or "Stop" on Mac.
- **Acceptance:**
  - [ ] Rings with phone in silent + DND.
  - [ ] Stop from Mac ends ring within 1 s.

---

## Notifications

### UC-08 Receive phone notification on Mac [F-5.1, F-5.4]
- **Main flow:** App posts notification → listener filters (per-app rules) → sends to Mac with
  app name, icon (cached), title, text, actions → Mac shows native notification.
- **Alternate:** `VISIBILITY_SECRET` → app name only unless opted in. MessagingStyle → sender
  names kept. Disconnected → not queued beyond a short, bounded buffer (decision in SPEC).
- **Acceptance:**
  - [ ] p95 latency Android → Mac < 500 ms same Wi-Fi.
  - [ ] Icon sent once per package+version.
  - [ ] Tandem's own and system-noise notifications never forwarded.

### UC-09 Act on / reply to notification from Mac [F-5.2]
- **Main flow:** Owner clicks an action or types a reply → `NotificationAction{key, index, replyText?}`
  → phone fires PendingIntent with RemoteInput bundle.
- **Alternate:** Notification already gone on phone → Mac shows "no longer available".
- **Acceptance:**
  - [ ] Reply to WhatsApp and Signal works end-to-end.

### UC-10 Dismiss sync [F-5.3]
- **Acceptance:**
  - [ ] Dismiss on phone removes Mac notification < 1 s, and vice versa.

### UC-11 Configure per-app filter and privacy [F-5.1, F-5.4]
- **Main flow:** Owner toggles apps on/off (phone), toggles "hide content on Mac lock screen"
  (Mac: while the Mac is locked, notifications show the app name only), toggles "show secret
  notifications" (phone: forward content of `VISIBILITY_SECRET` notifications).
- **Acceptance:**
  - [ ] Filter change applies to the next notification without reconnect.

---

## Clipboard

### UC-12 Copy on Mac, paste on phone [F-6.1, F-6.3]
- **Main flow:** Owner copies text → Mac detects changeCount → sends clip → phone writes clipboard.
- **Alternate:** Concealed/transient type (password manager) → never sent. > 1 MiB → not sent,
  Mac shows hint.
- **Acceptance:**
  - [ ] Concealed items never appear in a pcap-decrypted test log or on the phone.
  - [ ] No echo loop (phone does not send it back).

### UC-13 Send text phone → Mac clipboard [F-6.2, F-6.3]
- **Main flow:** Owner uses share sheet / QS tile / "Send to Mac" text selection / in-app button
  → Mac writes `NSPasteboard`.
- **Acceptance:**
  - [ ] All four entry points work on Android 10+ without accessibility.

---

## Files and photos

### UC-14 Send file Mac → phone [F-7.1, F-7.2]
- **Main flow:** Owner drags file onto menu window / Share extension / Finder Service →
  `FileOffer` → phone auto-accepts (trusted) or asks → chunks → SHA-256 verified → saved to
  `Download/Tandem/`.
- **Acceptance:**
  - [ ] Filenames sanitized (no path traversal, no hidden/reserved names).
  - [ ] Partial files never visible in the destination folder.

### UC-15 Send file phone → Mac [F-7.1, F-7.3]
- **Main flow:** Share sheet or in-app picker → offer → Mac writes `~/Downloads/Tandem/`.
- **Acceptance:** same as UC-14, mirrored.

### UC-16 Resume interrupted transfer [F-7.1]
- **Main flow:** Connection drops mid-transfer → reconnect → receiver reports offset → sender
  resumes → final hash verified.
- **Acceptance:**
  - [ ] 4 GB both ways with a forced disconnect midway; SHA-256 matches.
  - [ ] Notifications during transfer still < 500 ms p95 (flow control).

### UC-17 Browse and download phone photos on Mac [F-7.4]
- **Main flow:** Owner opens Photos → paged listing → thumbnails (LRU cached) → download
  original(s) via file transfer.
- **Acceptance:**
  - [ ] 10 000-item library scrolls without loading all thumbnails.
  - [ ] Cache respects size cap.

---

## Messaging, contacts, calls

### UC-18 Read SMS conversations on Mac [F-8.1, F-8.3]
- **Main flow:** Initial paged sync → watermark → ContentObserver pushes new messages → Mac
  thread list with contact names/photos.
- **Acceptance:**
  - [ ] New incoming SMS visible on Mac < 2 s.

### UC-19 Send SMS from Mac [F-8.2]
- **Main flow:** Owner composes → chooses SIM (multi-SIM) → phone sends multipart → sent /
  delivered status back to Mac.
- **Acceptance:**
  - [ ] Failure (no signal) reported to Mac.

### UC-20 Handle incoming call from Mac [F-8.4]
- **Main flow:** Phone rings → Mac shows caller (contact name if known) within 1 s → Owner
  answers / declines / later hangs up from Mac → audio stays on phone.
- **Acceptance:**
  - [ ] Answer and hang up from Mac work.

### UC-21 Place call from Mac [F-8.4]
- **Main flow:** Owner clicks a number → phone places call via `ACTION_CALL`.
- **Acceptance:**
  - [ ] Works with phone locked / app backgrounded (within Android BAL rules), or explains why not.

---

## Mirroring and input

### UC-22 Mirror phone screen on Mac [F-3.3, F-9.1, F-9.2]
- **Main flow:** Owner clicks "Mirror" → phone shows MediaProjection consent → Owner accepts on
  phone → media ticket issued → media mTLS connection → H.264 stream → Mac window.
- **Alternate:** Mac click only posts a "Mirror to <Mac>?" prompt on the phone; nothing is
  captured and no ticket is issued until the Owner accepts on the phone. Owner declines or
  ignores the prompt (30 s) → Mac shows "Mirroring declined on phone".
- **Acceptance:**
  - [ ] 1080p ≥ 30 fps, e2e latency < 120 ms on 5 GHz.
  - [ ] pcap-audit passes during mirroring with canary on screen.
  - [ ] Rotation handled without restart.
  - [ ] A Mac mirror request without an on-phone accept never starts capture or issues a ticket.

### UC-23 Control phone from Mac [F-9.3]
- **Main flow:** During an active user-started mirror session with on-phone indicator, Owner
  clicks/scrolls/types in the mirror window → INPUT frames → AccessibilityService injects.
- **Acceptance:**
  - [ ] Input without an active session is ignored and logged.
  - [ ] Coordinates correct in portrait, landscape, and letterboxed windows.

---

## Development

### UC-25 Developer runs the security audit suite [test strategy]
- **Main flow:** Developer runs canary procedure → captures traffic → `pcap-audit`, `mitm-lab`,
  `nmap`, downgrade checks, conformance → single pass/fail report.
- **Acceptance:**
  - [ ] One command per tool; CI runs the automatable subset on every PR touching `core/*`.

---

# Abuse cases (each must fail closed)

| ID | Attacker goal | Expected system behaviour | Verified by |
|---|---|---|---|
| AC-01 | Active MITM with wrong or swapped certificate | Handshake fails on pin mismatch; no application data sent; visible error | mitm-lab |
| AC-02 | Passive eavesdropping | Only TLS 1.3 records; canary never in capture | pcap-audit |
| AC-03 | Replay `PairRequest`, brute-force secret, use expired secret, proof for another key | Rejected; attempt burned; 4th attempt rejected; window expires | mitm-lab, unit tests |
| AC-04 | Unpaired device probes Mac port; TLS 1.2 / resumption / 0-RTT downgrade | Handshake fails outside pairing window; downgrade rejected | mitm-lab, `openssl s_client` |
| AC-05 | Track the Mac across days via Bonjour | TXT has only `v=1` + daily rotating HMAC ID; no name/fingerprint | unit tests, vectors |
| AC-06 | Inject input without a user-started mirror session | INPUT frames ignored + logged | integration test |
| AC-07 | Crash or exploit parser with malformed frames | Frame rejected, connection closed; fuzzers 24 h no crash | Jazzer, libFuzzer |
| AC-08 | Hijack media connection (missing/reused/expired ticket, other session's ticket) | Rejected | mitm-lab, unit tests |
| AC-09 | Use a lost/stolen paired phone | Owner revokes on Mac; next handshake fails | integration test |
| AC-10 | Harvest secrets/content from logs | Release logs contain no secrets, bodies, notification text, clipboard | log-lint rule, log audit |
| AC-11 | Trigger a debug/test-only protocol path (echo, canary-injection, debug channel) in a release build | No such path exists: debug and release builds speak an identical protocol; an unknown payload type closes the connection | SPEC review, proto schema scan, release audit |
