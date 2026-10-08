# ADR-010: Mac-initiated reconnect hint (PRD Appendix C.3)

- **Status:** Proposed
- **Date:** 2026-10-08
- **Issue:** E20-13
- **Inputs:** E20-03 spike ([`../spikes/cdm-presence.md`](../spikes/cdm-presence.md)), E20-12 measurements (pending)

## Context

PRD Appendix C.3 asks whether the Mac should be able to trigger a reconnect, for example through a
Bluetooth LE hint, when the phone has lost the control connection. Facts the choice must respect:

- The phone is always the TLS client and the Mac the only listener (ADR-002). The Android app opens
  no listening sockets (invariant 4).
- No application data crosses a socket that has not completed mTLS with a pinned peer
  (invariant 1). Trust is bound to SPKI fingerprints only (invariant 3).
- Discovery data is already a hint only and rotates daily (PRD F-3.5).
- The phone already restarts and redials from several independent triggers: the foreground service,
  network callbacks (E20-07), Mac-driven heartbeats (F-3.4), exponential backoff, and the
  `WakeReconnectTrigger` (screen on, Doze exit and app foreground kicks, `ReconnectStrategy.kick`).
- The E20-03 spike found that CompanionDeviceManager presence observation does not support Wi-Fi
  devices and cannot restart a killed app for a Wi-Fi-only Mac. An association alone adds no
  exemption the unrestricted-battery onboarding does not already give.

## Options

**(a) No hint. Rely on the foreground service, network callbacks, wake triggers, Mac-driven
heartbeats and backoff**
- Pros: no new radio surface, no new permission, no new trust or threat-model surface, nothing new
  to test beyond what exists.
- Cons: after a long idle the phone may take up to the backoff cap (30 s) to redial a Mac that woke
  first, unless a wake or network trigger fires.

**(b) The Mac emits a rotating BLE advertisement that the phone observes (CDM or BLE scan) and
answers by dialing the Mac itself**
- The phone stays the only dialer. The advertisement carries a daily rotating identifier derived
  like F-3.5, a random BLE address, no device name and no service data beyond the rotating id.
- Pros: could shorten reconnect after Mac wake.
- Cons: new radio surface on both sides, battery cost, trackability and spoofing (an advertisement
  can only prompt a dial, never confer trust), new permissions (owner-gated, Q20), a BLE bond
  outside the QR-only pairing model (ADR-004), and a new STRIDE row in E02-01.

**(c) Any phone-side GATT server or other inbound channel**
- **Rejected.** It is equivalent to a phone listener and violates invariant 4.

## Decision (proposed)

Ship **(a)** in v1. Record **(b)** as a v2 option, to be reopened only if the measured data below
fails its gate. **(c)** is rejected.

BLE, in any option, carries no application data, no keys and no stable identifiers (invariant 1).
At most it carries a daily rotating id that a stranger cannot link across days and that has no
authority: the phone's response to it is an ordinary dial through the full mTLS and pin check, and
a pin mismatch or unknown peer still fails closed (invariant 5).

## Evidence

| Gate | Result |
|---|---|
| E20-03: presence-based restart for a Wi-Fi-only Mac | No-go (documented API limit; on-device confirmation pending). See the spike |
| E20-12: Mac-wake reconnect p95 below 5 s | TODO: measured p95 and device matrix |
| E20-12: overnight Doze gate | TODO: pass or fail and device matrix |

The decision is finalized when the E20-12 manual gate data exists. If both gates pass, (a) stands
and this ADR moves to Accepted with the numbers filled in. If either fails, reopen (b) and see the
requirements below.

## If (b) is later accepted

- A daily rotating advertisement identifier derived like F-3.5, a random (resolvable or
  non-resolvable) BLE address, no device name, no service data beyond the rotating id.
- A STRIDE row is added to E02-01 before any follow-up issue starts.
- Follow-up issues are filed in E72 before Phase 7 starts.

## Consequences

- No Mac or phone code changes. F-4.1 wording about CDM presence restart is superseded by the E20-03
  outcome and should be updated when this ADR is accepted.
- E20-16 (CDM association, presence restart) is not needed for v1. See the spike and Q20.
