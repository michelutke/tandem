# USB transport design (E72-05) — AOA vs. adb reverse

Issue: GitHub #403 / backlog `E72-05` (`docs/planning/backlog/phase-7.yaml`). Branch
`e72-05-usb-transport-spike`. Status: **proposed, needs owner approval before E72-06 / E72-10 start.**

## Context

F-10.3 carries the same framed mTLS protocol over a USB cable (speed, no-Wi-Fi, client-isolated
networks). Constraints that decide the option:

- Invariant 4: the Android app opens no listening sockets. ADR-002: the phone is the TLS client, the
  Mac is the sole listener (one port, D-03). Invariants 1-3: mTLS with a pinned SPKI on every
  transport; no relaxed or plaintext USB mode.
- `TandemSession` (E12-11, E12-12) is transport-agnostic and sits on `ByteStream` /
  `ByteStreamConnection` (E00-19, E00-25), so a USB transport only has to supply a byte stream under
  the existing TLS + framing stack.

## Go/no-go summary

| # | Item | Result |
|---|---|---|
| 1 | `adb forward` (Mac listens, phone-side listener) | **NO-GO** — needs a phone-side listening socket (invariant 4) |
| 2 | `adb reverse` (phone app connects out to `127.0.0.1:P`, adbd tunnels to the Mac listener) | **GO — chosen for v1** |
| 3 | AOA (Mac USB host, bulk endpoints, no sockets) | **GO technically, deferred** — needs a new Mac TLS-over-custom-stream stack |
| 4 | Any USB mode weaker than mTLS + pin | **NO-GO** (invariants 1, 2, 3, 5) |

## Option A: `adb reverse` (chosen)

Mac runs `adb reverse tcp:P tcp:P` for an attached, authorised phone (P = the Mac's listener port).
The phone app opens an ordinary outbound `SSLSocket` to `127.0.0.1:P`; adbd carries the bytes over
USB to the Mac's `127.0.0.1:P`, which the existing `NWListener` already serves.

- **Invariant 4.** The app listens on nothing; it is a plain TCP client. The device-side loopback
  listener belongs to `adbd` (a system daemon), not the app, and is created by the Mac. Owner to
  confirm this reading of invariant 4 (see questions).
- **Invariants 1-3, 5.** Traffic reaches the same listener, so the same handshake runs: client cert
  required, SPKI pin check, `VersionHello`, fail closed. Any other phone-local app can also connect to
  `127.0.0.1:P` on the device; it reaches only the mTLS listener and fails the pin check, the same
  exposure as a LAN peer. No new listener, no new auth path, no code in `core/*` that sees "USB".
- **Effort.** Phone: a `ByteStream` over a socket to a fixed loopback address (the E12-11 production
  path with a different host). Mac: no new connection stack; a small `AdbReverseManager` that spawns
  `adb`, watches `adb track-devices` and runs/removes the reverse rule. E72-10 shrinks to that
  manager plus `ByteStreamConnection` wiring tests.
- **Cost.** The user must enable Developer options + USB debugging and accept the Mac's adb RSA
  prompt; USB debugging widens the phone's attack surface for as long as it stays on. The Mac needs an
  `adb` binary: bundle Android platform-tools (Apache 2.0, must be signed and notarised with the app)
  or require the user to point at an existing install. Sandbox implications for launching `adb` are
  for E72-10 to confirm; the app must not weaken its entitlements beyond that.
- **Throughput.** adb tunnels reach tens of MB/s on USB 2.0 high-speed, enough to beat Wi-Fi for
  file/photo transfer. Not measured here; E72-06 manual gate verifies the 5 s Hello target.

## Option B: AOA (deferred)

Mac acts as USB host (IOUSBHost / libusb), sends the AOA control requests (get-protocol, identify,
start accessory), then talks over a bulk IN/OUT pair. The phone app receives
`USB_ACCESSORY_ATTACHED` and calls `UsbManager.openAccessory`; no sockets exist anywhere.

- **Pros.** No Developer options or adb; cleanest fit for invariant 4; no adb dependency.
- **Cons.**
  - TLS must run over a raw bulk stream. On the phone this means `SSLEngine` over `ByteStream`
    (feasible). On the Mac, Network.framework cannot place TLS on a custom byte transport, so the
    existing `NWConnection`/`NWListener` mTLS stack cannot be reused; it would need swift-nio-ssl
    (`docs/spikes/swift-nio-ssl-fallback.md`, currently unused) or a loopback bridge, which would be
    a second listener (invariant 2). This contradicts E72-10's "existing stack runs unchanged".
  - Mac USB-host entitlement (`com.apple.security.device.usb`), bulk-transfer framing (packet size,
    zero-length packets) and per-OEM accessory-mode quirks; accessory mode can drop adb on some
    devices; an Android attach permission dialog per accessory/app.
  - A second, separately audited pin-checking TLS path doubles the security review surface.

## Decision

**v1: `adb reverse` only.** It is the only option where USB reuses the single audited listener and
the unchanged TLS/pinning stack. AOA is revisited only if owner feedback shows USB debugging is a
blocker, as its own spike on a Mac TLS-over-custom-stream design.

## Design rules for E72-06 / E72-10

1. **Paired reconnect only.** Pairing stays on the QR/LAN path; the USB path never accepts an
   unpinned peer (phone side) and the Mac listener's pairing window is unchanged (SPEC §2).
2. **No discovery.** Device port = Mac listener port (known from pairing). The phone tries
   `127.0.0.1:P` when attached; failure is an ordinary connection error, no fallback to another mode.
3. **Mac sets up the reverse rule**, removes it on detach/quit, and treats `adb` failure as "USB
   unavailable" (visible status), never as a reason to relax anything.
4. **Pin mismatch / unknown peer / version mismatch** fail closed with the same visible error as on
   Wi-Fi (invariant 5); logs follow invariant 7 (no payloads, no adb output containing serials in
   release builds).
5. **Transport selection** (USB vs Wi-Fi when both exist) is a `TandemSession` policy outside this
   spike; prefer USB when the Hello succeeds there.

## Unresolved questions

- Is an `adbd` loopback listener created by the Mac acceptable under invariant 4 (app opens none)?
- Bundle platform-tools or require a user-supplied `adb`?
- Is a Developer-options prerequisite acceptable for F-10.3 (P2), or is AOA required?
- Does the Mac listener port stay stable across launches (needed for a fixed device-side port)?
