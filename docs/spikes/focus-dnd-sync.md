# Focus/DND sync design (E72-03) — Mac Focus to Android interruption filter mapping

Issue: GitHub #401 / backlog `E72-03` (`docs/planning/backlog/phase-7.yaml`). Branch
`e72-03-focus-dnd-note`.

## Context

F-10.2 specifies that the Mac Focus state should toggle phone DND via `NotificationManager.setInterruptionFilter`. This note designs the macOS source API, Android target API, and which transport channel carries the state change.

## Go/no-go summary

| # | Item | Result |
|---|---|---|
| 1 | macOS Focus state API: `INFocusStatusCenter` (Intents, macOS 12+) with one-time user authorization; boolean only, no change notification (poll) | **GO, with requirements** (`NSFocusStatusUsageDescription`, Communication Notifications entitlement) |
| 2 | Android `NotificationManager.setInterruptionFilter` available without new permissions (runtime or manifest) | **GO** |
| 3 | Direction is Mac → phone only per PRD F-10.2 | **CONFIRMED** |
| 4 | Transport channel identified | **GO: TandemSession control channel** |

## Design

### 1. macOS Focus state source

The supported public API is `INFocusStatusCenter.default` (Intents framework, macOS 12.0+):

- **Authorization:** `requestAuthorization(completionHandler:)` prompts the user once; `authorizationStatus` reports `notDetermined`, `restricted`, `denied` or `authorized`. Tandem requests it when the first session attaches the Focus sender. Anything other than `authorized` is "capability unavailable": nothing is sent.
- **Reading:** `focusStatus.isFocused` is an optional `Bool`: `true` when a Focus is on and the app is not in its Allowed Apps list. It is boolean only (no Focus name or mode). `nil` means unavailable.
- **Change observation:** none is documented, so Tandem polls `focusStatus` (2 s) and sends only on change.
- **Info.plist:** `NSFocusStatusUsageDescription` (string) is required before using `INFocusStatusCenter`.
- **Entitlement:** Apple's sample requires the Communication Notifications capability (`com.apple.developer.usernotifications.communication`) on the app target, plus authorized User Notifications for the `INShareFocusStatusIntent` path. The entitlement key name is the capability's standard key; no dedicated Apple page for it was found.
- **Sources:**
  - https://developer.apple.com/documentation/intents/infocusstatuscenter
  - https://developer.apple.com/documentation/bundleresources/information-property-list/nsfocusstatususagedescription
  - https://developer.apple.com/documentation/usernotifications/handling-communication-notifications-and-focus-status-updates

Not used: `NSWorkspace.accessibilityDisplayOptions` (an accessibility API with no Focus key) and the undocumented `com.apple.donotdisturbd` defaults domain (private, unreliable, sandbox-hostile).

### 2. Android interruption filter target

On Android, `NotificationManager.setInterruptionFilter(int interruptionFilter)` sets the global DND state. The corresponding states:

- **Focus ON:** `INTERRUPTION_FILTER_PRIORITY` — only priority conversations interrupt.
- **Focus OFF:** restore the filter that was active before sync toggled it (or `INTERRUPTION_FILTER_ALL` if sync was never applied).

No new permissions required: the app already holds `android.permission.ACCESS_NOTIFICATION_POLICY` (granted for E30-* notification listener work). `setInterruptionFilter` respects this permission.

### 3. Message shape and carrying channel

**Protocol message:** Add a `FocusState` message to `tandem/v1/feature/focus_sync.proto`:

```protobuf
message FocusState {
  bool on = 1;  // true: Focus is active (DND ON)
}
```

**Channel:** Carry `FocusState` over the existing `TandemSession` control channel (same as media-control messages per E72-02). No separate channel needed; this is a lightweight state change, not high-frequency data.

**Direction:** Mac → phone unidirectional. Phone does not emit or update Focus state.

**Frequency:** Send `FocusState` on every Focus change (coalesced to once per network RTT, not per keystroke if OS batches notifications).

### 4. Security and correctness

- **Constant-time comparison:** Not applicable; boolean state has no secret material.
- **Invariant 1 (mTLS pinning):** `TandemSession` is already mTLS-pinned; `FocusState` rides the same connection.
- **Invariant 8 (user-started session):** Focus sync requires an active, user-started mirror session (E12-*) — Focus is not applied unless mirroring is active. This is enforced by the `TandemSession` state machine.
- **Capability unavailable:** If the Focus state API fails on macOS (authorization denied or restricted, or `isFocused` is `nil`), treat as "capability unavailable" and do not send `FocusState` messages.

## Outcome

**APPROVED for implementation in E72-04 (Android) and E72-09 (macOS).**

All acceptance criteria for E72-03 are met:
- Focus-state source API (`INFocusStatusCenter`) confirmed, with one-time authorization, usage-description key and entitlement.
- Android target API (`setInterruptionFilter`) confirmed available without new permissions.
- Direction (Mac → phone) confirmed per PRD.
- Carrying channel chosen: `TandemSession` control channel, with new `focus_sync.proto` message.

The design is ready for protocol implementation (E72-04/E72-09 depend on this note).

> **Signing note (2026-10-05):** `INFocusStatusCenter` authorization needs the Communication Notifications
> capability (`com.apple.developer.usernotifications.communication`). That entitlement requires a
> provisioning profile, so it is **not** in `TandemApp.entitlements` for the ad-hoc/unsigned CI and dev
> builds (an ad-hoc app claiming a restricted entitlement is refused at launch). Without it, authorization
> fails and Focus sync reports "capability unavailable" and sends nothing. Release signing must add the
> capability, plus its `mac-entitlements.allowlist` entry (E72-09).
