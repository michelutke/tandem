# Tandem Wire Protocol Specification

**Status:** Draft v1 — sections are added incrementally as their owning backlog issue (see
`docs/planning/backlog/*.yaml`) is completed. The [section map](#section-map) below lists every
planned section; a section marked `TBD` has not been written yet and MUST NOT be treated as
normative until it is.

Where this document conflicts with `docs/PRD.md`, this document and
`docs/planning/decisions.md` win (`docs/planning/decisions.md` D-40; `CLAUDE.md`). Every
normative statement here is traceable to a PRD functional requirement (`F-x.y`), a decision row
(`D-nn`), or an acceptance criterion (`AC-nn`) in the backlog; those references are given inline.

## Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119). Every one of these key words in this document
is normative; prose that does not use one of them is explanatory, not a requirement.

All multi-byte integers on the wire are big-endian unless a section states otherwise. Byte counts
are given in decimal; "1 MiB" always means exactly 1 048 576 bytes (2^20).

### Section anchors

Every `##`-level section heading below has a stable Markdown anchor derived by the standard GitHub
slug rule: lowercase the heading text, drop characters other than letters, digits, spaces and
hyphens, then replace runs of whitespace with a single hyphen. For example "Framing and envelope"
resolves to `#framing-and-envelope`. Anchors are part of this document's contract: once a section
is written, its heading text (and therefore its anchor) MUST NOT change without updating every
`.proto` comment and backlog row that cites it. Anchors for `TBD` sections are reserved now so
that `.proto` files and other SPEC sections can cite them ahead of time.

## Section map

| # | Section | Anchor | Status |
|---|---|---|---|
| 1 | Handshake and TLS profile | `#handshake-and-tls-profile` | TBD in E01-01 |
| 2 | Pairing | `#pairing` | TBD in E01-02 |
| 3 | Framing and envelope | [`#framing-and-envelope`](#framing-and-envelope) | Written (this issue, E01-03) |
| 4 | Channels and flow-control credits | `#channels-and-flow-control-credits` | TBD in E01-04 |
| 5 | Errors and close codes | [`#errors-and-close-codes`](#errors-and-close-codes) | Written (this issue, E01-05) |
| 6 | Versioning and capability negotiation | `#versioning-and-capability-negotiation` | TBD in E01-06 |
| 7 | Heartbeat | `#heartbeat` | TBD in E01-07 |
| 8 | Discovery TXT record | `#discovery-txt-record` | TBD in E01-08 |
| 9 | Media ticket | `#media-ticket` | TBD in E01-09 |
| 10 | Timeouts, connection limits and resource caps | `#timeouts-connection-limits-and-resource-caps` | TBD in E01-22 |
| 11 | Untrusted peer strings (display sanitization) | `#untrusted-peer-strings-display-sanitization` | TBD in E01-23 |
| 12 | Media frame semantics | `#media-frame-semantics` | TBD in E61-01 (extends §9, Phase 6) |
| 13 | Input events | `#input-events` | TBD (Phase 6, epic E62) |
| 14 | SMS channel | `#sms-channel` | TBD (Phase 5, epic E50) |
| 15 | Contacts channel | `#contacts-channel` | TBD (Phase 5, epic E51) |
| 16 | Calls channel | `#calls-channel` | TBD (Phase 5, epic E52) |
| 17 | Key rotation | `#key-rotation` | TBD (Phase 7, epic E70) |

Sections 1–11 are the Phase 0 `SPEC.md` v1 set (`docs/planning/traceability.md`, "`SPEC.md` v1"
row). Sections 12–17 are reserved slots for later phases so that earlier sections' numbering and
anchors never change; new sections are always appended after the last row in this table, never
inserted between existing rows.

---

## Framing and envelope

*(E01-03 · PRD F-3.2 · AC-07 · no invariant references)*

This section defines the byte-level frame format used on every mTLS connection (control, F-3.1,
and media, F-3.3) once the TLS handshake has completed, and the wire-contract shape of the
`Envelope` that every frame carries. The `Envelope` protobuf message itself (field numbers, types)
is defined in `protocol/proto/tandem/v1/envelope.proto` (E01-10); this section is normative for
its shape and every receiver's required behavior.

### Frame format

A frame is:

```
frame = length_prefix envelope_bytes
length_prefix = u32 big-endian
envelope_bytes = length_prefix octets, a serialized Envelope message
```

- `length_prefix` is an unsigned 32-bit big-endian integer counting the number of `Envelope` bytes
  that follow — that is, it excludes the 4 prefix bytes themselves.
- The maximum permitted value of `length_prefix` is 1 048 576 (1 MiB, 2^20).
- A receiver MUST compare `length_prefix` against the 1 MiB maximum before allocating any buffer
  sized from it. Allocating (or reserving) a buffer using an unchecked, attacker-supplied length is
  forbidden regardless of how large the underlying transport buffer already is.

### Envelope fields

`Envelope` carries, at the wire-contract level:

- `channel` — identifies which of the nine F-3.2 channels (`CONTROL`, `NOTIFY`, `CLIPBOARD`,
  `FILES`, `SMS`, `CONTACTS`, `CALLS`, `INPUT`, `STATUS`; enumerated normatively in §4,
  `#channels-and-flow-control-credits`) this frame belongs to.
- `seq` — an unsigned 64-bit counter (`uint64`), maintained independently per channel and per
  direction (i.e. each side of a connection keeps its own outgoing counter per channel). The first
  frame a side sends on a given channel carries `seq = 1`; each subsequent frame that side sends on
  that same channel increments its own counter by exactly 1. `seq = 0` is never valid on the wire
  (§ Sequence and acknowledgement violations, below). Counters on different channels, and the two
  directions' counters on the same channel, are independent of one another.
- `ack` — the highest `seq` value received on that channel, in contiguous order, from the peer.
  Before any frame has been received on that channel in that direction, `ack` is 0, meaning
  nothing has been received yet (unambiguous, since `seq` is never 0 on the wire). `ack` MUST NOT
  advance past a gap: if a receiver has seen `seq` 1 and 3 but not yet 2, `ack` for that channel
  stays at 1 until `seq = 2` arrives, at which point it becomes 3. This is the contract the E11
  channel multiplexer (E11-05, E11-06) implements against.
- `payload` — a `oneof` carrying exactly one typed application message, whose set of legal types is
  fixed by the protocol version in effect on the connection (E01-06).

### Rejection cases

Each of the following is a framing-level protocol violation. On detecting any of them, a receiver
MUST close the connection with close code `MALFORMED_FRAME` (§5, `#errors-and-close-codes`). The
specific case is a local diagnostic reason only: it is never sent on the wire and it is never a
separate close code (`docs/planning/decisions.md` D-13 — no parser oracle on the wire).

| Case | Local reason | Trigger |
|---|---|---|
| Oversize | `TOO_LARGE` | `length_prefix` > 1 048 576 |
| Bad length | `BAD_LENGTH` | `length_prefix` == 0 |
| Truncated | `TRUNCATED` | the connection's byte stream ends via an orderly close (EOF, or a TLS `close_notify`) after at least 1 byte of a new frame — the length prefix or the envelope bytes — has arrived, but before that frame is complete. A TCP reset (RST) is a transport-layer error, not a framing rejection: it MUST be reported by the transport layer as a connection error, never as `MALFORMED_FRAME`/`TRUNCATED` (E11-02, E11-04). |
| Malformed | `DECODE_FAILED` | the `length_prefix` bytes received fail to decode as a well-formed `Envelope` protobuf message |
| Unknown channel | `UNKNOWN_CHANNEL` | `channel` is not one of the nine values enumerated in §4, including the reserved `CHANNEL_UNSPECIFIED = 0` value |
| Unknown payload | `UNKNOWN_PAYLOAD_TYPE` | the `oneof payload` is unset, or set to a payload type this receiver's protocol version does not define (AC-11) |

A receiver MUST check `length_prefix` against the 1 MiB maximum (the oversize case) before reading
or allocating anything for the payload; in particular, an oversize `length_prefix` MUST be
rejected using only the 4 prefix bytes, without waiting for or buffering any of the (attacker
supplied, arbitrarily large) claimed payload. An orderly close (EOF or TLS `close_notify`) that
arrives exactly at a frame boundary — zero bytes into a new frame — is a normal, non-error
connection close, not a `TRUNCATED` violation.

Before both sides have exchanged `VersionHello` (§6, E01-06) on the **control connection**, the
only legal payload on that connection is `VersionHello` itself; any other payload arriving first
MUST be rejected as `UNKNOWN_PAYLOAD_TYPE`, closing with `MALFORMED_FRAME`. On the **media
connection**, the first frame MUST be `MediaHello` (§9); any other first payload MUST be rejected
as `UNKNOWN_PAYLOAD_TYPE` (closing with `MALFORMED_FRAME`), per E60-02/E60-03.

### Sequence and acknowledgement violations

Regression is defined relative to the **ack watermark**, not relative to the highest `seq` value
ever seen: the ack watermark for a channel and direction is the current value of `ack` as defined
under Envelope fields above (the highest `seq` received in contiguous order so far, 0 before
anything has arrived). A `seq` value above the watermark that has not been seen before is never a
violation, even if it is lower than the highest `seq` received so far on that channel — that is
exactly the gap-fill case, and it advances `ack` past that value and past any further
already-received, now-contiguous values.

A receiver MUST close the connection with close code `MALFORMED_FRAME` (local reason
`SEQ_REGRESSION`) on receiving, for any channel:

- a frame with `seq = 0` — there is no valid frame numbered zero, since the first frame a side
  sends on a channel carries `seq = 1`;
- a frame whose `seq` is less than or equal to the current ack watermark for that channel (it
  duplicates or falls behind a value already folded into `ack`); or
- a frame whose `seq` exactly repeats a value already received above the watermark but not yet
  folded into `ack` (a duplicate of a frame still held back by an earlier gap).

Worked example (single channel, one direction; arrival order left to right):

| `seq` arrival order | What happens | `ack` after each arrival |
|---|---|---|
| 1, 3, 2 | all three accepted: 1 sets the watermark; 3 is a gap, held; 2 fills the gap, which then folds in the already-received 3 | 1, 1, 3 |
| 1, 2, 2 | 1 and 2 accepted; the second 2 is at the watermark (2 ≤ 2) | 1, 2, **fatal** |
| 1, 3, 1 | 1 accepted; 3 is a gap, held; the second 1 is at or below the watermark (1 ≤ 1) | 1, 1, **fatal** |

A receiver MUST also close the connection with close code `MALFORMED_FRAME` (local reason
`SEQ_REGRESSION`) on receiving, for any channel, an `ack` value greater than the highest `seq` this
side has itself sent on that channel so far — the peer is acknowledging a frame that was never
sent.

Sequence numbers are a strict per-channel, per-direction contract (E11-05/E11-06 acceptance: "a
repeated or regressing seq triggers the E01-03-defined behaviour"); a sender that would otherwise
need to send a `seq` at or below the watermark, or repeat an already-received above-watermark
value, has no valid frame to send and MUST NOT send one. This `SEQ_REGRESSION` local reason, its
watermark-relative definition, and its assignment to the existing `MALFORMED_FRAME` close code
rather than a new one, are recorded in `docs/planning/decisions.md` D-57.

### No fragmentation on the control connection

On the control connection, an `Envelope` is never split across more than one frame: every frame's
`length_prefix` bytes are exactly one complete, self-contained `Envelope`. A receiver MUST buffer
at most one partial (not yet fully received) frame per connection, and that partial frame is at
most 1 048 576 + 4 = 1 048 580 bytes.

The only fragmentation mechanism anywhere in this protocol is the media-connection `MediaFrame`
access-unit fragmentation rule owned by §12 (`#media-frame-semantics`, E61-01,
`docs/planning/decisions.md` D-26): an encoded access unit larger than 960 KiB is split into at
most 8 fragments of at most 960 KiB each, sharing one `pts`, contiguous and in index order: 8
fragments of at most 960 KiB each reassemble to at most 7.5 MiB (8 × 960 KiB = 7 680 KiB = 7.5 MiB)
by construction, within the 8 MiB media access-unit cap of §10
(`#timeouts-connection-limits-and-resource-caps`, E01-22). That rule applies only to `MediaFrame` on
the media connection; it does not change anything stated above for the control connection, and it
does not raise the 1 MiB per-frame maximum defined in this section, which still bounds the size of
each individual fragment's frame.

---

## Errors and close codes

*(E01-05 · PRD F-3.2 · AC-04, AC-07, AC-13 · invariant 5)*

This section is the single canonical enumeration of protocol-level close codes. Every other
section, `.proto` file, and test vector that needs to name a fatal protocol condition MUST use one
of the names in the table below; no other part of this document or the codebase may introduce a
new close code outside this table.

**Invariant 5 (fail closed with a visible error) governs every row in this table.** A close code
MUST NOT trigger a plaintext, reduced-security, or unauthenticated retry of any kind (invariant 2):
closing is always the end of that connection attempt, never a downgrade. A `PairRejected.reason`
of `UNSPECIFIED` (0) or any value outside `{REJECTED_BY_OWNER, PAIRING_UNAVAILABLE}` MUST be
treated as fatal and mapped locally to `PAIRING_FAILED` with generic pairing-failed text; it MUST
NOT be treated as non-fatal and MUST NOT be presented as revealing a specific reason. The same rule
applies to any wire-carried code a future version of this protocol adds: a value the receiving
implementation does not recognize MUST be treated as fatal, MUST produce a generic
connection-error message, and MUST NOT be guessed at.

### Pre-authentication closes are not surfaced per connection

The listening side (the Mac) MUST NOT surface a per-connection UI notification for a close on a
connection whose peer has not yet passed the TLS pin check (§1, E01-01) — for example, one of many
unsolicited connection attempts closed with `PIN_MISMATCH`, `PROTOCOL_TIMEOUT`, or `LIMIT_EXCEEDED`
while listening, before that peer's key was ever recognized. Each such close MAY be counted in an
aggregate, non-blocking counter (e.g. "N rejected connections today"), but MUST NOT pop a dialog or
alert per attempt: doing so would let an unauthenticated network attacker drive the Mac's UI
(AC-13, `docs/planning/decisions.md` D-59).

Once a peer has passed the pin check — even if the connection then fails a later, post-pin step
such as the `VersionHello` comparison or the hello-stage deadline — its close MAY instead be shown
in an already-visible status area rather than a popped dialog (E12-10
`failClosedErrorScenario_menuOpened_showsVersionMismatchText`): a pinned peer's `VERSION_MISMATCH`
or hello-stage `PROTOCOL_TIMEOUT` is about a device the user already recognizes, not network noise,
and a status-area indicator satisfies the "MUST be shown in the UI" requirement on such a row.
`VERSION_MISMATCH` in particular can only ever occur once the pin check has passed (`VersionHello`
is exchanged after TLS completes), so the pre-pin-check scoping above never applies to it.

Everywhere this section says a close code's text "MUST be shown in the UI", that requirement
applies to (a) the dialing side (the phone), for which each connection attempt — a control-session
dial, or a media-session dial made concurrently with an already-open control session (§9, E60-02)
— is the direct result of a single user-visible action, and (b) either side when the close tears
down an already-authenticated, Ready session or any connection whose peer already passed the pin
check. It does not require the Mac to surface every pre-pin-check connection attempt from the
network.

### Local reason vs. wire code

A close code is always determined locally by whichever side detects the fault, and is always the
value used for that side's logs, its local UI error mapping, and the `closeCode` field asserted by
this protocol's test vectors (E01-16, E01-19). Several close codes additionally group a set of
finer-grained local reasons that are diagnostic only and are never sent to the peer in any form
(`docs/planning/decisions.md` D-13, D-17): `MALFORMED_FRAME` (reasons `TOO_LARGE`, `BAD_LENGTH`,
`TRUNCATED`, `DECODE_FAILED`, `UNKNOWN_CHANNEL`, `UNKNOWN_PAYLOAD_TYPE`, `SEQ_REGRESSION`,
`FRAGMENT_VIOLATION`, §3, §12), `PAIRING_FAILED` (reasons `EXPIRED`, `ATTEMPTS_EXHAUSTED`,
`BAD_PROOF`, `REJECTED_BY_OWNER`, `TIMEOUT`, `MALFORMED`, §2), and `TICKET_REJECTED` (reasons
`MISSING`, `REUSED`, `EXPIRED`, `OTHER_SESSION`, §9).

There is no dedicated close-notice message in this version of the protocol: no message type
carries a generic `closeCode` field to the peer. A close code is inferred by the peer only through
one of four existing signals:

1. **`PairRejected.reason`** — sent immediately before the close on a pairing-candidate connection
   (§2, E01-11), collapsing the six `PAIRING_FAILED` local reasons above per the rule below.
2. **`Revoke`** — received on an already-trusted session, the receiver deletes its trust record for
   the sender (the peer authenticated on that session) and closes that session with `REVOKED` (§2,
   E01-11; `docs/planning/decisions.md` D-23).
3. **The `VersionHello` comparison itself** — `VERSION_MISMATCH` needs no separate signal: each side
   locally compares the peer's advertised protocol major version, already exchanged per §6
   (E01-06), against its own.
4. **A TLS handshake-failure alert** (`certificate_unknown` / `bad_certificate`) on an ordinary,
   non-pairing-candidate dial — the dialing side maps the alert it receives to `PIN_MISMATCH`, or,
   if it had previously pinned that peer, to `REVOKED` ("no longer paired", E12-16; see row 7
   below). There is no persistent "revoked" record on the rejecting side: deleting a trust record
   removes all memory of the peer (`docs/planning/decisions.md` D-23), so the rejecting side cannot
   distinguish an unrecognized key from a previously-revoked one and always produces
   `PIN_MISMATCH`. This mapping does not apply on a **pairing-candidate** dial (the QR flow, §2):
   E12-16 scopes the `PIN_MISMATCH`/`REVOKED` alert mapping to non-pairing connections. If the
   phone's own pin check against the QR `fp` has already passed (the Mac's identity is not in
   question) and a handshake-failure alert then arrives, the phone maps it to `PAIRING_FAILED`
   (a generic local reason — the pairing window closing, being full, or otherwise unavailable)
   rather than `PIN_MISMATCH`.

No other close code in the table below has any wire signal at all: for `MALFORMED_FRAME`,
`CREDIT_VIOLATION`, `TICKET_REJECTED`, `PROTOCOL_TIMEOUT`, and `LIMIT_EXCEEDED`, the peer observes
only that the connection closed, with nothing to distinguish which of these five occurred. This is
a deliberate generalization of "no parser oracle on the wire" (`docs/planning/decisions.md` D-13)
beyond `MALFORMED_FRAME` to every close code that has no signal above. A future protocol revision
MAY add a wire-transmitted signal for one of these five; until it does, they MUST NOT be inferred
by the peer from anything other than the four signals above.

`PairRejected.reason` collapses the six `PAIRING_FAILED` local reasons onto exactly two wire
values: local reason `REJECTED_BY_OWNER` maps to wire value `REJECTED_BY_OWNER`; every other local
reason (`EXPIRED`, `ATTEMPTS_EXHAUSTED`, `BAD_PROOF`, `TIMEOUT`, `MALFORMED`) maps to wire value
`PAIRING_UNAVAILABLE`. The rejecting Mac MAY show its own owner the specific local reason in its
pairing UI (that detail never leaves the Mac); the rejected phone MUST derive its pairing-failure
text only from whichever of the two wire values it received, never from an assumption about which
local reason caused it.

### Close-code table

Numeric IDs are frozen once released: an implementation, `.proto` file, or test vector MUST NOT
reuse or renumber an ID once it ships. IDs below are assigned in the order each code was ratified
(review cycle 3 for IDs 1–7, cycle 4 for IDs 8–9; `docs/planning/decisions.md` D-13, D-20). ID `0`
is reserved and MUST NOT be assigned to any code, so that a future shared `CloseCode` enum can use
it as an explicit `UNSPECIFIED` default consistent with every other enum in this protocol
(`Channel`, `PairRejected.reason`).

| ID | Name | Occurs when (triggering condition) | User-visible behavior |
|---|---|---|---|
| 1 | `VERSION_MISMATCH` | The `VersionHello` protocol major version fields exchanged per §6 differ (E01-06). | Security-relevant: MUST be shown in the UI — this always occurs after the peer's pin check has passed (`VersionHello` is only exchanged after TLS completes), so the pre-pin-check scoping above never suppresses it; a status-area indicator satisfies this requirement (E12-10). Text MUST name the version mismatch specifically (e.g. "this Mac/phone needs an app update"), never a generic error. |
| 2 | `PIN_MISMATCH` | The TLS verify callback (§1, E01-01) computes a peer SPKI fingerprint that does not match the trust store: on the Mac, this fires outside an open pairing window (during an open window an unrecognized key is accepted only for the pairing exchange, §2); on the phone, which has no inbound connections at all (invariant 4) and therefore never opens a pairing window, this fires on every connection whose peer key does not match the trust-store pin or, during pairing, the QR `fp`. | Security-relevant: MUST be shown in the UI (subject to the pre-pin-check scoping above), not only logged (UC-05). Text MUST be specific ("this device's identity changed / is not trusted"), never a generic error, and MUST NOT suggest retrying without re-pairing. |
| 3 | `MALFORMED_FRAME` | Any framing-level rejection in §3 (oversize, bad length, truncated, decode failure, unknown channel, unknown payload type, seq/ack regression), or a §12 `MediaFrame` fragmentation violation on the media connection — index gap, fragment-count change, count greater than 8, interleaving with another `pts`, or a reassembled size over 8 MiB (local reason `FRAGMENT_VIOLATION`, `docs/planning/decisions.md` D-26). | Generic connection-error message; MUST NOT be presented as a pin or version problem. |
| 4 | `CREDIT_VIOLATION` | A sender transmits on a channel with zero remaining credit, or a receiver's outstanding grant would exceed its cap (§4, E01-04). | Generic connection-error message; MUST NOT be presented as a pin or version problem. |
| 5 | `PAIRING_FAILED` | Any pairing-window rejection in §2 (expired, attempts exhausted, bad proof, rejected by owner, malformed request), including the `PairRequest` 10 s deadline of §10/E01-22 (local reason `TIMEOUT`), which burns one pairing attempt like any other failed attempt (E01-02, E14-02). | MUST be shown in the pairing UI (it is the direct result of a user-initiated pairing attempt); text MUST NOT distinguish which of the six local reasons occurred. |
| 6 | `TICKET_REJECTED` | The media connection's `mediaTicket` (§9, E01-09) is missing, already consumed (reused), expired, or was issued to a different control session's peer. | Generic connection-error message on the media connection only; MUST NOT affect or close the control session, and MUST NOT be presented as a pin or version problem. |
| 7 | `REVOKED` | This side processes a valid `Revoke` on an already-trusted session and deletes its trust record for that peer (§2, E01-11; `docs/planning/decisions.md` D-23), closing that session with `REVOKED`; or this side dials a peer that no longer recognizes its client key and the resulting TLS alert is mapped, per E12-16, to `REVOKED` — but only if this side had previously pinned that peer (otherwise the same alert maps to `PIN_MISMATCH`, since there is no persistent "revoked" record: an unrecognized key is indistinguishable from a never-known one, `docs/planning/decisions.md` D-23). | Security-relevant: MUST be shown in the UI (subject to the pre-pin-check scoping above), not only logged (UC-05). Text MUST be specific ("this device was unpaired"), distinct from `PIN_MISMATCH`'s "not trusted" wording. |
| 8 | `PROTOCOL_TIMEOUT` | Any deadline in §10 (E01-22) elapses without the required message: TLS handshake (10 s), `VersionHello` (5 s), or `MediaHello` on a media connection (5 s). The `PairRequest` 10 s deadline on a pairing-candidate connection is deliberately excluded here: exceeding it closes with `PAIRING_FAILED` (local reason `TIMEOUT`, row 5) instead, because it also burns one of the three pairing attempts — a `PROTOCOL_TIMEOUT` close never burns a pairing attempt. Heartbeat-based dead-connection detection (§7, E01-07: 45 s of silence on an established control session) is a separate, local transport-liveness event, not a close code: it triggers the phone's reconnect flow (E20-06) directly and MUST NOT be reported as `PROTOCOL_TIMEOUT`. | Generic connection-error message; MUST NOT be presented as a pin or version problem. If this occurs on a connection whose peer already passed the pin check (e.g. a recognized Mac that stalls before sending `VersionHello`), it MAY additionally be surfaced in the status area (E12-10) rather than suppressed as pre-pin-check network noise. |
| 9 | `LIMIT_EXCEEDED` | A peer or source address exceeds a connection-level cap in §10 (E01-22): more than 8 concurrent not-yet-Ready connections, or more than 2 from one source IP (excess sockets closed on accept, before the TLS handshake); a source IP with 10 or more failed handshakes within 60 s (refused for 60 s); a second concurrent pairing-candidate connection while one is already in flight (rejected in the verify callback without burning a pairing attempt, §2, E01-02); an older control session replaced by a newer Ready session for the same peer SPKI, closing the older one (E01-22); or a second media connection opened for a control session that already has one (E60-04). | Generic connection-error message; MUST NOT be presented as a pin or version problem. |

---
