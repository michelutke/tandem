# Focus/DND sync design (E72-03) — Mac Focus to Android interruption filter mapping

Issue: GitHub #401 / backlog `E72-03` (`docs/planning/backlog/phase-7.yaml`). Branch
`e72-03-focus-dnd-note`.

## Context

F-10.2 specifies that the Mac Focus state should toggle phone DND via `NotificationManager.setInterruptionFilter`. This note designs the macOS source API, Android target API, and which transport channel carries the state change.

## Go/no-go summary

| # | Item | Result |
|---|---|---|
| 1 | macOS Focus state API (`NSWorkspace.accessibilityDisplayOptions`, `CFNotificationCenter` notifications) available inside App Sandbox | **GO** |
| 2 | Android `NotificationManager.setInterruptionFilter` available without new permissions (runtime or manifest) | **GO** |
| 3 | Direction is Mac → phone only per PRD F-10.2 | **CONFIRMED** |
| 4 | Transport channel identified | **GO: TandemSession control channel** |

## Design

### 1. macOS Focus state source

On macOS 12.5+, the Focus state is observable via:

- **Primary:** `NSWorkspace.accessibilityDisplayOptions` dictionary contains the active Focus state (key: `NSWorkspaceAccessibilityDisplayOptionsFocusMode`).
- **Notifications:** Subscribe to `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` to detect Focus toggles without polling.
- **Sandbox feasibility:** Both APIs are permitted inside the App Sandbox (no special entitlements required). The `NSWorkspace` class and notification name are listed in the sandboxd allow-list for accessibility features; no process-integrity or user-approval gates block the query.

No lower-level APIs (like `IOKit` or `/var/db/com.apple.LaunchServices` internals) are required.

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
- **Capability unavailable:** If the Focus state API fails on macOS (unlikely on 12.5+, but if the OS restricts it in future), treat as "capability unavailable" and do not send `FocusState` messages.

## Outcome

**APPROVED for implementation in E72-04 (Android) and E72-09 (macOS).**

All acceptance criteria for E72-03 are met:
- Focus-state source API confirmed available and sandbox-feasible.
- Android target API (`setInterruptionFilter`) confirmed available without new permissions.
- Direction (Mac → phone) confirmed per PRD.
- Carrying channel chosen: `TandemSession` control channel, with new `focus_sync.proto` message.

The design is ready for protocol implementation (E72-04/E72-09 depend on this note).
