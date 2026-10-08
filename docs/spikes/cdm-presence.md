# CompanionDeviceManager presence for a Wi-Fi-only Mac (E20-03)

Issue: GitHub #203 / backlog `E20-03` (`docs/planning/backlog/phase-2.yaml`). Branch
`e20-03-cdm-spike-and-adr`. Status: **desk research only; on-device confirmation outstanding** (see
[Evidence status](#evidence-status)).

## Go/no-go summary

| Item | Result |
|---|---|
| Presence-based restart of the killed foreground service (E20-16 presence part) | **NO-GO** |
| Association alone as a restart or battery mechanism | **Not worth building** (adds nothing the product does not already have) |
| E20-16 | **Recommend closing as won't-do.** Not implemented. Adding the association needs new permissions, which are owner-gated (open question Q20) |

## Context

PRD F-4.1 says the Android service "uses `CompanionDeviceManager` presence observation where
available to restart after kills". The Mac is a Wi-Fi-only peer: it is a TLS server found through
Bonjour, never a Bluetooth device the phone is bonded to. The phone is the only dialer and opens no
listening sockets (invariant 4); trust is a pinned SPKI only (invariant 3).

## Findings

### (a) Can presence observation restart the killed service for a Wi-Fi-only Mac? No

- `startObservingDevicePresence(ObservingDevicePresenceRequest)` reports only BLE range changes and
  Bluetooth connection changes. The reference states it verbatim: "WiFi devices are not
  supported." BLE presence is "based on scanning for device with the given address", and classic
  Bluetooth presence "is triggered when the device connects/disconnects".
  Source: [CompanionDeviceManager](https://developer.android.com/reference/android/companion/CompanionDeviceManager).
- The system binds the app's `CompanionDeviceService` only on `EVENT_BLE_APPEARED`,
  `EVENT_BT_CONNECTED` or `EVENT_SELF_MANAGED_APPEARED`, and unbinds it when the matching
  disappeared event arrives.
  Source: [CompanionDeviceService](https://developer.android.com/reference/android/companion/CompanionDeviceService).
- A Mac that does not advertise BLE therefore never produces a presence event. Making it advertise
  is the BLE hint option in ADR-010 (option b): new radio surface, rejected for v1.
- Self-managed associations (API 33+, `REQUEST_COMPANION_SELF_MANAGED`) have no OS-observed
  presence at all. The companion app must report appeared and disappeared itself, so a killed app
  has nobody to report. They cannot restart a killed process.
- Android 16 (API 36) deprecates `startObservingDevicePresence(String)` and
  `CompanionDeviceService.onDeviceAppeared()` in favour of the request-object overload and
  `onDevicePresenceEvent`. The BLE and Bluetooth-only scope is unchanged.
  Source: [Companion device pairing, Keep companion apps awake](https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing#keep-awake).
- Binding the `CompanionDeviceService` raises the process priority (resists the low-memory killer),
  but only while the device is present, which never happens for this peer.

### (b) What does an association alone buy us? Nothing we lack

Documented benefits of an association:

| Benefit | Needs | Already covered |
|---|---|---|
| Start a foreground service from the background | `REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND` or `REQUEST_COMPANION_RUN_IN_BACKGROUND` | Yes: the same exemption list includes "The user turns off battery optimizations for your app" |
| Start the app from the background, use data in background | `REQUEST_COMPANION_RUN_IN_BACKGROUND`, `REQUEST_COMPANION_USE_DATA_IN_BACKGROUND` | Yes: onboarding asks for unrestricted battery (F-4.1, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` already declared) |
| Raised process priority while bound | Presence event | No presence events for this peer |

Sources: [Restrictions on starting a foreground service from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start),
[Companion device pairing](https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing).

Costs of adding an association: a system user-consent dialog at pairing, a display name and icon
shown by the OS, up to five new manifest permissions, a `CompanionDeviceService` declaration, and
a second lifecycle (association id) to keep in step with unpair (E14-12). A kill still needs an
external trigger to restart, and the project's triggers are independent of CDM: boot and package
replaced receivers, network callbacks (E20-07), `WakeReconnectTrigger` (screen on, Doze exit and
foreground kicks) and Mac-driven heartbeats.

Caveat: the exemptions are only worth having if the user declines unrestricted battery.
Onboarding asks for it, so an association would at best be a partial fallback for a state the
product already steers users away from. Whether an association also affects Doze or App Standby
network limits is not documented on the pages above and was not verified.

### (c) Cost and privacy of Mac BLE advertising (input for E02-01)

Not measured. Design-level notes for the threat model:

- New radio surface on the Mac, with its own entry in the STRIDE table: tracking by a nearby
  observer, spoofed advertisements triggering phone dials (a DoS or battery drain vector), and
  battery cost on both sides (continuous Mac advertising, OS-level BLE scans on the phone).
- Privacy follows F-3.5: a daily rotating identifier derived from the Mac SPKI and the day, a
  random BLE address, no device name, no service data beyond the rotating id. Even so, an
  advertisement is observable by strangers and must never be trusted: it can only prompt the phone
  to dial, and the mTLS pin check still decides everything (invariants 1, 3 and 5).
- BLE carries no application data, no keys and no stable identifiers. See ADR-010.
- Android's presence API for BLE devices expects the OS to resolve the device address (bonded device
  plus Resolvable Private Address when rotating). A bonded BLE relationship with the Mac adds a
  second pairing ceremony outside the QR-only model (ADR-004) and a second identity binding, so this
  is not free to adopt.

### (d) Invariants 3 and 4

- A CDM association id or MAC address is a local OS handle for the association. It must never be a
  trust input: trust stays bound to SPKI fingerprints only (invariant 3). If E20-16 were ever built,
  the id would live outside the trust store and creating or removing it would leave the trust-store
  record unchanged (already in the E20-16 acceptance).
- `CompanionDeviceService` is a system-bound service for callbacks, not a socket. CDM adds no
  phone-side listener. Any BLE design where the phone hosts a GATT server or other inbound channel
  is rejected as equivalent to a listener (invariant 4).

## New permissions (owner-gated, not added)

Associating, even without presence, would need some of the following. None are added by this spike
and none go on any allowlist. Listed as open question Q20 in
[`open-questions.md`](../planning/open-questions.md).

| Permission | Purpose | Level |
|---|---|---|
| `REQUEST_COMPANION_SELF_MANAGED` | Create a self-managed association (API 33+) | normal |
| `REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND` | FGS start exemption | normal |
| `REQUEST_COMPANION_RUN_IN_BACKGROUND` | Background start exemption (deprecated in favour of the above for FGS) | normal |
| `REQUEST_COMPANION_USE_DATA_IN_BACKGROUND` | Data in background | normal |
| `REQUEST_OBSERVE_COMPANION_DEVICE_PRESENCE` | Presence callbacks (BLE or Bluetooth only, unusable here) | normal |

## Evidence status

The acceptance asks for device, API level and log evidence on API 31, 33, 34, 35 and 36. This
document is built from the current official Android documentation only; no prototype was run on a
physical device. The no-go rests on a documented API limit ("WiFi devices are not supported"), not
on an observed failure, so on-device confirmation is a cheap sanity check rather than a deciding
experiment. The remaining step is a throwaway prototype on one device per API level that creates a
self-managed association, kills the app, and checks that no `CompanionDeviceService` bind occurs
without an app-reported presence event. Until then #203 stays open.

## Decisions for the owner

1. Accept no-go and close E20-16 as won't-do (recommended).
2. If an association is still wanted as a fallback for users who refuse unrestricted battery, approve
   the permission set above first (Q20).

## References

- ADR-010 Mac-initiated reconnect hint: [`../adr/ADR-010-mac-reconnect-hint.md`](../adr/ADR-010-mac-reconnect-hint.md)
- PRD F-3.4, F-3.5, F-4.1, Appendix C.3
