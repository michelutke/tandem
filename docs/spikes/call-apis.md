# Call APIs (E52-02): detection, caller number, control and placement

Issue: backlog `E52-02` (`docs/planning/backlog/phase-5.yaml`). Owner decisions of 2026-10-08 are
recorded as D-83 in `docs/planning/decisions.md`. Unblocks E52-03, E52-04 and E52-05.

## Go/no-go summary

| # | Item | Result |
|---|---|---|
| 1 | Call state without extra permission beyond `READ_PHONE_STATE` | **GO**: `TelephonyCallback.CallStateListener` |
| 2 | Caller number on API 31+ | **GO, with the call-screening role**; without it the number is absent ("Unknown caller" on the Mac) |
| 3 | Answer, decline, hang up | **GO**: `TelecomManager.acceptRingingCall()` and `endCall()` with `ANSWER_PHONE_CALLS` |
| 4 | Place a call from the background | **GO, unverified on device**: `TelecomManager.placeCall` with `CALL_PHONE`, confirmed by a state change, with a tap-to-call notification fallback |
| 5 | `READ_CALL_LOG` | **NO-GO**: not used |

## Chosen APIs

### Detection

`TelephonyManager.registerTelephonyCallback` with `TelephonyCallback.CallStateListener`
(`READ_PHONE_STATE`, minSdk 33 so the callback API is always available). It reports `RINGING`,
`OFFHOOK` and `IDLE` and delivers the current state on registration. It carries no number on API 31+.
It also cannot tell an outgoing dialling call from a connected one, so an outgoing call is reported
`DIALING` until it ends; the Mac still offers Hang Up for `DIALING`.

Rejected: `PhoneStateListener` (deprecated, needs a Looper thread, also numberless on API 31+),
`ACTION_PHONE_STATE_CHANGED` with `EXTRA_INCOMING_NUMBER` (needs `READ_CALL_LOG`).

### Caller number

A `CallScreeningService` (`TandemCallScreeningService`) held through
`RoleManager.ROLE_CALL_SCREENING`, granted once by the user in Settings (Caller ID). It reads
`Call.Details.getHandle()` and nothing else.

- It never blocks, silences, rejects or alters a call: every call, incoming or outgoing, gets the
  default `CallResponse` (allow).
- The number goes to an in-memory relay that the gateway reads when the state callback fires. The two
  callbacks race, so on `RINGING` the gateway waits up to 500 ms for a late screening callback. The
  number is dropped when the call ends.
- Without the role the number is absent and the Mac shows "Unknown caller".
- No `READ_CALL_LOG`, so no Play call-log policy declaration, and no default-dialer role.

### Answer, decline, hang up

`TelecomManager.acceptRingingCall()` answers. `TelecomManager.endCall()` declines a ringing call and
hangs up a dialling or active one. `endCall()` is deprecated from API 29 but works for apps holding
`ANSWER_PHONE_CALLS` and needs no `InCallService`. Audio stays on the phone.

### Placement

`TelecomManager.placeCall(tel: uri, extras)` with `CALL_PHONE`, and the SIM's `PhoneAccountHandle` in
`EXTRA_PHONE_ACCOUNT_HANDLE` for a non-default subscription. Unlike `startActivity(ACTION_CALL)` it is
not an activity start by the app, so the background-activity-start rules do not apply to the call
itself. Android can still drop a background placement silently, so the gateway treats a placement as
done only if the telephony state leaves `IDLE` within 5 s. Otherwise it reports `Blocked`, and the
handler posts a high-priority "Tap to call" notification whose tap starts `ACTION_CALL` through a
`PendingIntent` (the tap is a user-visible foreground action) and answers `NEEDS_PHONE_TAP`.

No `USE_FULL_SCREEN_INTENT`: Android 14+ restricts it to calling and alarm apps, and the notification
tap is enough for the fallback. The number appears only in the private notification body; the
lock-screen version has none.

Address checks, the 5 s rate limit and the SIM check run before any placement (SPEC.md Calls
channel "Place call").

## Permissions per API level

| Permission | Use | API levels |
|---|---|---|
| `READ_PHONE_STATE` | call state callback, SIM lookup | 33+ (minSdk) |
| `ANSWER_PHONE_CALLS` | `acceptRingingCall`, `endCall` | 33+ |
| `CALL_PHONE` | `placeCall`, tap-to-call `ACTION_CALL` | 33+ |
| `BIND_SCREENING_SERVICE` (service guard, not requested) and `ROLE_CALL_SCREENING` | caller number | 33+ |
| `POST_NOTIFICATIONS` (already declared) | tap-to-call notification | 33+ |

## Still to verify on a physical API 34+ phone (go/no-go)

1. A ringing call yields the number once the role is held.
2. A call placed from the Mac while the app is backgrounded and the screen locked either starts or
   falls back to the notification, never fails silently.
3. `endCall()` declines a ringing call and the caller hears a normal rejection.

## Protocol gap

`CallEvent` has no way to say an outgoing call connected, so outgoing calls stay `DIALING` until
`ENDED` and the Mac in-call bar (shown for `ACTIVE`) does not appear for them. Fixing it needs a
signal Android only gives to an `InCallService` (default dialer), which is out of scope.
