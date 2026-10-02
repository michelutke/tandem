# ADR-009: Multi-Mac uses one independent control connection per Mac, no phone-side broker

- **Status:** Accepted
- **Date:** 2026-10-02
- **Issue:** E72-07

## Context

PRD F-10.4 (v2+, out of scope for v1) lets one phone stay connected to several paired Macs at the
same time. PRD Appendix C.2 asked: one control connection per Mac, or a phone-side broker? The
backlog requires an accepted architecture before any multi-Mac implementation issue is opened. This
is an architecture question, not an owner question (it is not in `docs/planning/open-questions.md`).

Facts the choice must respect:

- The phone is always the TLS client and the Mac the server (ADR-002); the Android app opens no
  listening sockets (invariant 4).
- Trust is a pin of the peer's SPKI fingerprint, stored per paired Mac (invariant 3). The phone
  presents one client identity to every Mac. Each Mac pins that identity independently.
- The connection state machines (E12-08 phone, E12-09 Mac) are per connection. E12-09 is already
  per-peer on the Mac, which holds several phones.
- Discovery already supports several Macs: the phone computes one candidate `id` per stored Mac
  fingerprint (SPEC Discovery TXT record), and discovery is a hint only.
- Control plus media connections per Mac pair (ADR-005); media tickets bind a media connection to
  one control session.

## Options

**(a) One independent control connection (plus optional media connection) per paired Mac**
- Pros: reuses the existing handshake, verify callback, pin check, state machine, heartbeat,
  rotation and revoke unchanged; a failure or revoke on one Mac cannot affect another; no new
  trust surface; no new message types.
- Cons: the phone holds N sockets and N heartbeats; features that act on "the Mac" need a target
  selection rule.

**(b) Phone-side broker (one phone component multiplexes peers, possibly relaying between Macs)**
- Pros: single place for routing policy.
- Cons: a second trust layer above the pinned connections; invites relaying data between Macs,
  which no pin ever authorized (invariant 1 spirit: a Mac would receive data it never paired for
  that originated at another peer); new state and failure modes; nothing in F-10.4 needs it.

## Decision

Option (a). Each paired Mac is an independent peer with its own connection set. There is no broker
and no cross-Mac relay: bytes received from one Mac are never forwarded to another.

### Trust and identity

- Trust store: one record per paired Mac keyed by its SPKI fingerprint (`name`, `lastSeen`),
  unchanged from SPEC. No schema change is needed for several records. IP addresses and device ids
  stay non-anchors (invariant 3).
- The phone presents the same client identity to every Mac. Key rotation (D-74 flow) therefore runs
  per connection; a phone rotation sends `KeyRotation` to each paired Mac as each connects, as the
  Mac already does for several phones (D-34). A Mac not connected at rotation time receives it on
  its next Ready session.
- Pairing is unchanged: one QR pairing per Mac, one pairing-candidate connection at a time on the
  Mac side. Pairing a second Mac never alters existing pins.

### Concurrent sessions

- Each Mac gets its own `ConnectionState` machine instance and `Flow<ConnectionState>`; the 10 s
  handshake deadline, `HelloExchange`, heartbeat and reconnect backoff run per Mac. State is never
  shared: `Failed`/`REVOKED`/`PIN_MISMATCH` on one Mac leaves others untouched.
- Phone-side caps: the SPEC §10 concurrent not-yet-Ready cap is per accepting side, so it does not
  limit phone dials. Implementation should still dial Macs staggered, not in a burst, to keep the
  phone's own socket and radio use bounded. The limit on simultaneously connected Macs is an
  implementation issue (proposal: 4), not a protocol rule.
- Foreground service, notification and battery implications are owned by the implementation epic.

### Discovery

- Unchanged: one `id` match per stored fingerprint yields a candidate address for that Mac only.
  A matched address is dialed expecting that Mac's pin; mismatch fails closed (invariant 5).

### Revoke semantics

- `Revoke` stays per connection: unpairing Mac A deletes only A's trust record on the phone and
  closes only A's session (`REVOKED`). A revoke received from A deletes A's record and no other.
- Unpair UI acts on exactly one Mac and names it. "Unpair all" is a loop of per-Mac revokes, with
  the same dangling-record handling per Mac as SPEC §2.

### Feature routing (what "to the Mac" means with several Macs)

- Data is scoped to its connection: replies, ACKs and Mac-originated requests (clipboard push, SMS
  send, file offers) return on the connection they arrived on only.
- Phone-initiated actions with a single target (send clipboard, send file, start mirror) require
  an explicit target Mac chosen by the owner; there is no implicit broadcast. Clipboard sync to
  several Macs is a user-visible per-Mac setting, off by default for newly paired Macs beyond the
  first, so content never reaches a Mac the owner did not intend.
- Mirror sessions (invariant 8): started per Mac, each with its own on-phone indicator naming the
  Mac. Whether two concurrent mirror sessions are allowed is deferred; the default is at most one.
- Phone notifications mirror to every connected Mac that has opted in; each Mac shows and dismisses
  them independently.

### UI implications (for `docs/design/ui-spec.md` when implemented)

- Paired-devices list with a per-Mac status row (connected, reconnecting, failed with reason) using
  the existing per-peer states and error mapping (PIN_MISMATCH and REVOKED text unchanged).
- Per-Mac actions: rename display label (local only, never a trust input), unpair, set as default
  target.
- Target picker where an action needs a Mac, defaulting to the last-used connected Mac.

## Consequences

- No protocol change, no new proto messages and no SPEC change are required for the architecture.
  Implementation issues add: phone-side multi-connection manager owning N state machines, target
  selection, per-Mac settings, and UI.
- Invariants 1 to 8 are preserved because every byte path remains a pinned, per-Mac mTLS session.
- Residual: a compromised paired Mac cannot reach other Macs through the phone, but anything the
  owner explicitly sends to it (per target selection) is visible to it.
- Follow-ups to open only after this ADR: manager and target-selection issues (Android),
  paired-devices UI, per-Mac clipboard setting, concurrent-mirror decision.
