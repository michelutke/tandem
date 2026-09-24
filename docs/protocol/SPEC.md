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
| 4 | Channels and flow-control credits | [`#channels-and-flow-control-credits`](#channels-and-flow-control-credits) | Written (E01-04) |
| 5 | Errors and close codes | [`#errors-and-close-codes`](#errors-and-close-codes) | Written (this issue, E01-05) |
| 6 | Versioning and capability negotiation | [`#versioning-and-capability-negotiation`](#versioning-and-capability-negotiation) | Written (E01-06) |
| 7 | Heartbeat | [`#heartbeat`](#heartbeat) | Written (E01-07) |
| 8 | Discovery TXT record | [`#discovery-txt-record`](#discovery-txt-record) | Written (E01-08) |
| 9 | Media ticket | [`#media-ticket`](#media-ticket) | Written (E01-09) |
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

## Channels and flow-control credits

*(E01-04 · PRD F-3.2 · UC-08, UC-09, UC-14, UC-15, UC-17, AC-11, AC-19 · invariant 2)*

This section enumerates the closed set of channels a `channel` field (§3, `#framing-and-envelope`)
may name, and defines the credit-based flow-control algorithm that keeps one channel's traffic from
starving another's — in particular, so a large FILES transfer cannot delay a NOTIFY frame.

### Channel enumeration

`Channel` numeric values are frozen once released, exactly as the close-code numeric IDs in §5: an
implementation or `.proto` file MUST NOT renumber or reuse a channel value once it ships (E01-10).
`CHANNEL_UNSPECIFIED` is reserved and MUST NOT be assigned to any channel, consistent with `0` being
reserved across every enum in this protocol (`Channel`, `PairRejected.reason`, close codes).

| ID | Name | Carries (informative; see E01-14 for the authoritative future-domain mapping) |
|---|---|---|
| 0 | `CHANNEL_UNSPECIFIED` | Reserved. Never a valid value on the wire (§3, `UNKNOWN_CHANNEL`). |
| 1 | `CONTROL` | `VersionHello`, `Heartbeat`, `CreditGrant`, `MediaTicketGrant`, pairing and rotation messages. |
| 2 | `NOTIFY` | Notification mirroring (F-5.1–F-5.4). |
| 3 | `CLIPBOARD` | Clipboard sync (F-6.1–F-6.3). |
| 4 | `FILES` | File transfer and the photo browser (F-7.1–F-7.4; see decision below). |
| 5 | `SMS` | SMS read/sync/send (F-8.1, F-8.2). |
| 6 | `CONTACTS` | Contacts sync (F-8.3). |
| 7 | `CALLS` | Call control (F-8.4). |
| 8 | `INPUT` | Remote input events (F-9.3). |
| 9 | `STATUS` | Device status, `Ring`/`RingStop` (F-4.3, F-4.4). |

This channel set is closed and exhaustive: the nine values above, plus the reserved
`CHANNEL_UNSPECIFIED = 0`, are the only channel values this version of the protocol ever defines.
There is no tenth `PHOTOS` channel: the photo browser's paged listings, thumbnail requests and
thumbnail results (F-7.4) are `FILES`-channel payloads, sharing `FILES`'s credit ledger with any
in-flight file transfer (`docs/planning/decisions.md` D-01; E41-01). A sender interleaving a large
file transfer with photo-browser traffic on `FILES` MUST round-robin its outgoing `FILES` frames per
logical stream (one transfer, or one browse/thumbnail request, is one stream) rather than fully
draining one stream before starting another, so a multi-gigabyte transfer cannot itself starve a
thumbnail response on the same channel (E41-01).

No channel value, message type, or payload exists anywhere in this protocol for debugging, echo,
loopback, or test-only purposes, in either a debug or a release build: debug and release builds
speak an identical protocol (`docs/planning/decisions.md` D-02). A payload type this receiver's
protocol version does not define — including any such hypothetical debug-only type — is rejected as
`UNKNOWN_PAYLOAD_TYPE` under the existing `MALFORMED_FRAME` close code (§3), never accepted or
specially recognized (AC-11).

### Credit accounting

The credit unit for every channel this section's ledger applies to is whole frames: one credit
permits the sender to transmit exactly one `Envelope` frame on that channel, independent of the
frame's payload size (up to the 1 MiB maximum of §3). This matches the unit `FileChunk` senders
already reason in (E40-03/E40-04: "one credit grant releases exactly the granted number of chunks").

Every channel except `CONTROL` (the exemption is defined below) has its own credit ledger, tracked
independently by each side for its own outgoing direction:

- **Per-channel cap.** For each of the eight feature channels (`NOTIFY`, `CLIPBOARD`, `FILES`, `SMS`,
  `CONTACTS`, `CALLS`, `INPUT`, `STATUS`), a receiver chooses its own cap for that channel: the
  maximum credit it will ever have outstanding to its peer on that channel at one time. A chosen cap
  MUST NOT exceed 64 credits; a receiver MAY choose a smaller cap for a given channel (for example, a
  lower `FILES` cap on a memory-constrained phone) to bound its own memory use. Because a frame is at
  most 1 MiB (§3), a channel whose cap is `n` credits bounds that channel's receive buffering
  (decoder → consumer, below) at `n` × 1 MiB.
- **Initial grant.** A new ledger for a feature channel starts with a balance equal to that channel's
  chosen cap.
- **Consume.** A credit is returned to the sender's balance — i.e. counted toward the replenishment
  trigger below — only once the channel's application-level consumer has actually taken the
  corresponding frame out of the receiver's decoder→consumer buffer, not merely once the frame has
  been decoded off the wire. This is what makes the cap a real bound on buffering: a stalled consumer
  stops replenishment, which in turn stops the sender once its outstanding credit is exhausted, so
  the buffer between decoder and consumer for that channel never holds more than `cap` frames (the
  bound stated above).
- **Replenishment.** `CreditGrant { channel, amount }` is the replenishment message (it rides the
  `CONTROL` channel like `Heartbeat` and `VersionHello`, defined in `control.proto`, E01-12, since it
  must never itself be subject to the credit system it manages). A receiver MUST send exactly one
  `CreditGrant` for a channel each time that channel's outstanding grant to its peer is consumed
  (per the rule above) down to half of the channel's cap or fewer — i.e. at the moment cumulative
  consumption since the last grant (or since the initial grant, if none has been sent yet) first
  crosses the halfway point, not on every frame consumed after that. `amount` MUST restore the peer's
  balance to exactly the channel's cap, never above it. The trigger then re-arms against this new,
  fully-replenished balance, so it fires again the next time consumption crosses that channel's
  halfway point.
- **Grant beyond the cap.** A `CreditGrant.amount` that would take the receiving side's own balance
  for that channel above its chosen cap is a protocol violation, not a local bookkeeping adjustment:
  the credit ledger MUST report the overflow rather than silently absorbing it, and the multiplexer
  MUST close the connection with the close code `CREDIT_VIOLATION` (§5, `#errors-and-close-codes`,
  row 4) on receiving it. Clamping such a grant to the cap and continuing, instead of closing, would
  leave the receiver silently unable to ever use credit it was told it has — effectively deadlocking
  that channel — which is why an over-cap grant closes rather than clamps.
- **Sender obligation.** A sender MUST NOT transmit a frame on a feature channel while its remaining
  credit for that channel is zero; it pauses that channel until a `CreditGrant` restores credit.
- **Violation.** A peer that transmits on a feature channel past the credit it was actually granted —
  the same close condition as an over-cap grant, above — MUST cause the receiver to close the
  connection with the close code `CREDIT_VIOLATION`. A receiver MUST NOT silently drop an
  over-credit frame instead of closing.
- **`CreditGrant` naming an ineligible channel.** A `CreditGrant.channel` naming `CONTROL`,
  `CHANNEL_UNSPECIFIED`, or any value outside the nine defined channels MUST be rejected with the
  close code `MALFORMED_FRAME`, local reason `UNKNOWN_CHANNEL` (§3) — `CONTROL` carries no credit
  ledger to grant against (below), and the other two values never name a real channel. A
  `CreditGrant.amount` of 0 is well-formed and MUST be treated as a no-op (ignored, not an error and
  not a violation).

### CONTROL is exempt from credit accounting

`CONTROL` carries no credit ledger at all and is exempt from every rule above: control and heartbeat
traffic (§7, `#heartbeat`) MUST NOT be backpressured by the credit system, both because it must never
be starved and because `CreditGrant` itself rides `CONTROL` — a credit-gated `CONTROL` channel could
deadlock. In its place, `CONTROL` has the separate, fixed-rate caps of §10
(`#timeouts-connection-limits-and-resource-caps`, E01-22): the phone answers at most one `Heartbeat`
per second, dropping faster ones silently with no reply, no error and no close
(`docs/planning/decisions.md` D-60); and non-`Heartbeat` `CONTROL` frames from a peer are capped at
60 per second per session, exceeding which closes the connection with `LIMIT_EXCEEDED`
(`docs/planning/decisions.md` D-61).

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

## Versioning and capability negotiation

*(E01-06 · PRD F-3.1 · AC-04 · invariant 5)*

This section defines `VersionHello`, the message each side of the control connection sends first,
and the required behavior on a version mismatch (fail closed, invariant 5) versus a capability
mismatch (feature-level degrade only, never a security downgrade).

### `VersionHello` fields

`VersionHello { major, minor, capabilities }` (`control.proto`, E01-12; `docs/planning/decisions.md`
D-63) carries exactly three fields:

- `major` — a `uint32` protocol major version. Two sides are version-compatible only if their
  `major` values are numerically equal; a difference in `major` is always fatal, regardless of
  `minor`. This version of the protocol sets `major = 1`. Because this field is a proto3 `uint32`,
  an unset field decodes as `0`; a peer whose `major` reads `0` (whether it never set the field, or
  deliberately set it to `0`) MUST be treated as a genuine major-version mismatch against this
  protocol's `major = 1` — proto3's default-value encoding MUST NOT be read as "no version stated"
  or otherwise given a pass. `major` is a separate concept from the TLS ALPN identifier `tandem/1`
  (§1, `docs/planning/decisions.md` D-19): ALPN is fixed at the TLS layer and never renegotiated
  within a session, while `major` is compared by the application after TLS completes, so a future
  major protocol revision can change one without necessarily changing the other. In this version both
  happen to read "1".
- `minor` — a `uint32` protocol minor version, additive within a `major`. Two sides with the same
  `major` but different `minor` values MUST still interoperate: a receiver on a lower `minor` MUST
  simply not receive whatever additive behavior a higher `minor` introduces, and a peer on a higher
  `minor` MUST remain compatible with a peer on any lower `minor` of the same `major` — a `minor` bump
  MUST NOT introduce a change serious enough to break an older peer of the same `major` (that always
  requires a `major` bump instead). This version of the protocol sets `minor = 0`.
- `capabilities` — a `uint64` bitmask of optional capability flags the sender supports. No bit is
  assigned a meaning in this version of the protocol: Phase 0 has no optional wire feature that needs
  negotiating. Every sender of this version MUST set `capabilities` to 0. A receiver MUST NOT act on,
  or gate any behavior on, any bit of `capabilities` in this version of the protocol — this holds even
  for a bit the receiver happens to recognize from a later draft, since no bit is normatively defined
  yet. A receiver MAY nonetheless record or expose the raw `capabilities` value it received (for
  example, alongside `lastSeen` in a peer's trust-store record, E12-14/E12-17) without that recording
  itself constituting "acting on" a bit. Once a future revision does assign bits, a receiver MUST
  always ignore any bit it does not recognize, never treating an unrecognized set bit as an error or
  a reason to close the connection. A future SPEC revision that assigns a capability bit documents it
  as an additive amendment to this section and MUST NOT repurpose or renumber a bit once shipped,
  using the same frozen-numbering discipline as close codes (§5) and channels (§4).

### Exchange rule

As §3 (`#framing-and-envelope`) already states: before both sides have exchanged `VersionHello` on
the control connection, the only legal payload on that connection is `VersionHello` itself; any other
payload arriving first MUST be rejected as `UNKNOWN_PAYLOAD_TYPE`, closing with `MALFORMED_FRAME`.
Each side MUST send its own `VersionHello` as the first frame it transmits on `CONTROL` (`seq = 1`,
§3) without waiting for the peer's, then compares once its own has been sent and the peer's has been
received. No application frame — on any channel — MAY be sent by either side before both hellos have
been exchanged.

### Version mismatch

If the `major` fields the two sides exchange differ, both sides MUST close the connection with the
close code `VERSION_MISMATCH` (§5, `#errors-and-close-codes`, row 1) and show a visible error naming
the version mismatch specifically. A difference in `minor` alone, with matching `major`, is never a
`VERSION_MISMATCH` (see Exchange rule and `minor`, above). As §5 already states, this comparison
needs no separate wire signal: each side determines the mismatch locally by comparing the peer's
advertised `major` against its own, once both hellos have been received.

### Capability mismatch

- A receiver MUST NOT act on any `capabilities` bit in this version (see above); it MAY still record
  or expose the raw value it received.
- A receiver that does not recognize a `capabilities` bit the peer set MUST ignore it (see above).
- A capability bit MAY cause a receiver to disable an optional feature it does not support, but a
  capability bit MUST NOT ever be used to weaken, bypass, or downgrade the TLS profile (§1), the SPKI
  pin check (§1), the pairing protocol (§2), or media-ticket validation (§9): those are fixed
  protocol invariants, never negotiable per-connection features (invariant 5).
- Because no capability bit is assigned in this version, this section documents the negotiation rule
  now so the exchange mechanism — and the "never weakens security" constraint on it — exists before
  any capability bit actually needs it.

---

## Heartbeat

*(E01-07 · PRD F-3.4 · UC-04 · no invariant references)*

This section defines the control connection's wire-level liveness contract. The reconnect strategy
itself (address selection, backoff) is out of scope here (E20). Liveness is asymmetric: the Mac (the
control connection's server side, ADR-002) drives it by sending `Heartbeat`; the phone (the client
side) only answers (`docs/planning/decisions.md` D-10, D-46). `Heartbeat {}` (`control.proto`,
E01-12) carries no fields; a `Heartbeat` frame is an ordinary `CONTROL`-channel `Envelope` like any
other, subject to §3's `seq`/`ack` rules and, per §4, `CONTROL`'s own rate caps rather than
credit-based flow control.

### Interval and dead-peer threshold

- The Mac MUST send one `Heartbeat` on `CONTROL` after 15 s have elapsed since it last sent any frame
  on that connection — not only a `Heartbeat`; any frame it sends resets this 15 s idle timer.
- The Mac MUST treat the control connection as dead if it has not received any frame — `Heartbeat` or
  otherwise — from the phone within 45 s (three missed 15 s intervals) of the last frame it received
  from the phone.
- Symmetrically, the phone MUST treat the control connection as dead if it has not received any frame
  from the Mac within 45 s of the last frame it received (see Silence measurement, below).
- Declaring a connection dead by either side under this rule is a local, transport-liveness
  determination, not one of the §5 close codes: it MUST NOT be reported as `PROTOCOL_TIMEOUT` or any
  other close code (`docs/planning/decisions.md` D-58; §5's `PROTOCOL_TIMEOUT` row states this
  explicitly). On declaring the connection dead, the Mac MUST close its side of the control
  connection; the phone, on declaring the same, treats its session as ended and reconnects per E20-06
  regardless of whether the underlying socket has itself already errored.

### Reply obligation

- The phone MUST reply with exactly one `Heartbeat` to every `Heartbeat` it receives, within 1 s of
  receipt.
- The Mac MUST NOT reply to a `Heartbeat` it receives — there is no ping-pong loop. A `Heartbeat`
  arriving at the Mac only resets the Mac's own silence timer (see below); it never itself causes the
  Mac to send a `Heartbeat` in response.
- Per §4 and §10 (`docs/planning/decisions.md` D-60), the phone answers at most one `Heartbeat` per
  second; if `Heartbeat`s arrive faster than that, the phone MUST drop the excess silently — no
  reply, no error, no close.

### Mac-side receive cap on incoming Heartbeats

Every `Heartbeat` the Mac receives from the phone — whether it is a reply to a Mac-sent `Heartbeat`
or one the phone sent unsolicited (above) — MUST count toward the same 60-per-second-per-session
`CONTROL` receive cap that §4/§10 (`docs/planning/decisions.md` D-61) applies to non-`Heartbeat`
`CONTROL` frames; exceeding it closes the connection with `LIMIT_EXCEEDED`, exactly as for any other
`CONTROL` frame over that cap (`docs/planning/decisions.md` D-66). This closes the gap D-61's
original wording left open: D-61 bounds only *non*-`Heartbeat` `CONTROL` frames, and D-60 bounds only
the phone's own *reply* rate, so neither, on its own, bounds a compromised-but-authenticated phone
sending unsolicited `Heartbeat`s to the Mac far faster than the reply-triggering 15 s interval. The
phone's own receive-side cap on `CONTROL` frames from the Mac keeps the `Heartbeat` exclusion as
originally stated in D-61: Mac-sent `Heartbeat`s are inherently bounded by the Mac's own 15 s send
interval, so the phone has no equivalent gap to close.

### Unsolicited heartbeats and Doze

- The phone MAY send an unsolicited `Heartbeat` after 15 s of its own idle sending time while the
  device is interactive, to help keep the Mac's silence timer reset independent of feature traffic.
- The phone MUST NOT hold a wake lock or schedule an alarm merely to send an unsolicited `Heartbeat`
  while the device is in Doze. An incoming Mac-sent `Heartbeat` still reaches the phone in Doze
  because the foreground service holding the control connection runs with the unrestricted-battery
  exemption, which keeps network access available; this section states only the wire-visible
  obligation, and the platform mechanics are E20-15's concern.

### Silence measurement

- The phone MUST measure silence on a sleep-inclusive monotonic clock (`elapsedRealtime`, never
  wall-clock time, so it cannot be fooled by a clock change or miscounted during Doze) and MUST
  evaluate the "> 45 s since the last received frame" condition at least on its own liveness timer
  firing, on Doze exit, and on screen-on.
- Any frame received on the control connection, not only a `Heartbeat`, resets the silence timer on
  both sides: a channel actively carrying feature traffic (`NOTIFY`, `FILES`, etc.) is itself proof of
  liveness and counts the same as a `Heartbeat` for this purpose.

### Doze expectation (E20-12 overnight gate)

While the phone is in Doze with its foreground service running and unrestricted battery access
granted, the control connection either: (a) stays up — Mac-sent `Heartbeat`s reach the phone and its
replies reach the Mac, so 45 s of silence is never observed on either side — or (b), if the Mac has
already declared the connection dead and closed it, the phone MUST reconnect (E20-06) within 5 s of
its next Doze maintenance window or of the screen turning on, whichever occurs first.

---

## Discovery TXT record

*(E01-08 · PRD F-3.5 · UC-03, AC-05 · invariants 1, 3)*

This section defines the `_tandem._tcp` Bonjour/mDNS TXT record the Mac advertises so an already
paired phone can find a candidate address on the local network, without giving an unpaired observer
a stable identifier to track the Mac by. Discovery is a hint only: it never establishes trust and
never bypasses the handshake's SPKI pin check (§1).

### TXT record contents

The TXT record MUST contain exactly two keys, `v` and `id`, and no others:

- `v` MUST be the literal string `1`. A receiver that only recognizes `v=1` MUST ignore an
  advertisement carrying any other value without raising an exception. `v` identifies the shape of
  this discovery record itself and is independent of the `CONTROL`-channel `VersionHello.major`/
  `.minor` of §6, which governs the protocol spoken once a connection is actually made.
- `id` MUST be the 8-byte rotating identifier defined below, encoded as exactly 16 lowercase
  hexadecimal characters (no `0x` prefix, no separators).
- The TXT record MUST NOT contain the Mac's name, its SPKI fingerprint, or any other value that is
  stable across days or that identifies the specific Mac to an observer who is not already paired
  with it (AC-05).

### Rotating identifier

- `dayIndex = floor(unixSecondsUTC / 86400)`, an integer computed from the current UTC time — never
  the device's configured time zone — so the same instant yields the same `dayIndex` on the Mac and
  every phone regardless of each device's local time zone.
- HMAC input: `dayIndex` encoded as an unsigned 64-bit big-endian integer (8 bytes), consistent with
  this document's default big-endian convention (Conventions, above). This 8-byte value is the entire
  HMAC message.
- HMAC key: the issuing Mac's own SPKI fingerprint — SHA-256 over its DER-encoded
  SubjectPublicKeyInfo, the same 32-byte value the trust store persists and pins (`docs/PRD.md`
  "SPKI fingerprint", F-1.1) — MUST be used as the HMAC key, not the raw SPKI DER bytes. A phone's
  trust store holds only this fingerprint for each paired Mac, never the DER, so the fingerprint is
  the only value both sides can compute this identifier from.
- `id = ` the first 8 bytes of `HMAC-SHA256(key = macSpkiFingerprint, message = dayIndex as 8-byte
  big-endian)`.
- The Mac (advertiser) and each phone (matcher) compute this identically. A phone paired with more
  than one Mac computes one candidate `id` per stored Mac fingerprint and compares each against every
  advertisement it observes.
- A phone MUST compare `id` byte-for-byte (as lowercase hex) against each of its own computed
  candidates; an advertised `id` using uppercase hex, mixed case, or any other encoding that does not
  match a candidate exactly MUST be treated as non-matching and ignored — a receiver MUST NOT
  normalize case (or otherwise canonicalize) an advertised `id` before comparing it.
- The Mac MUST switch to advertising the new day's `id` within 1 s of 00:00:00 UTC, and MUST
  advertise the `id` for the current UTC day (never a stale one computed before sleep) within 1 s of
  waking; neither transition may cancel an already-open connection (E21-02 implements both cases on
  macOS).

### Skew tolerance

A receiver MUST compute and accept the `id` values for `dayIndex-1`, `dayIndex`, and `dayIndex+1`
(three candidate ids per paired Mac), to tolerate the UTC day boundary and modest clock skew between
devices. A receiver MUST NOT accept an `id` computed from any `dayIndex` outside that ±1 day window.

### Discovery is a hint only

- Discovery data — the fact that a `v=1`/`id` record was seen, or that its `id` matched a paired
  Mac's expected value — MUST NOT be used to establish trust, MUST NOT supply any key material, and
  MUST NOT bypass or shortcut the mTLS handshake's SPKI pin check (§1, invariants 1, 3). A match only
  produces a candidate network address for the phone's reconnect strategy (F-3.4, E20-06); the pin
  check on the resulting connection attempt is the only trust decision, and it runs exactly as it
  would for any other candidate address — including one that turns out to belong to an attacker
  replaying a paired Mac's currently valid `id` at a different address (`docs/threat-model.md` §4.16).
- A malformed or unmatched TXT record (a wrong-length or non-hexadecimal `id`, an unrecognized `v`,
  or extra or missing keys) MUST be ignored without raising an exception and MUST NOT affect
  discovery of other, well-formed advertisements.
- **Residual risk.** The rotating `id` is a function only of the Mac's SPKI fingerprint and the
  current `dayIndex`, both of which a former (now revoked) peer already knows from having been
  paired: revocation deletes the *phone's* record of trusting the Mac (§2, `docs/planning/decisions.md`
  D-23), but it cannot make the Mac's SPKI fingerprint itself unknown to a phone that saw it while
  paired. A revoked device can therefore still compute the Mac's current `id` and recognize its
  advertisement (and, per E21-02, the Bonjour service instance name, which is derived from the same
  `id`) indefinitely — this is not a trust bypass, since recognizing an advertisement only ever
  yields a candidate address for an ordinary connection attempt that the pin check (now lacking the
  revoked device's key) will fail, but it is a tracking/presence-disclosure residual worth recording
  here alongside the mDNS-hostname residual already noted in `docs/threat-model.md` §4.16.

---

## Media ticket

*(E01-09 · PRD F-3.3 · UC-22, AC-08 · invariants 1, 3, 6)*

The media connection is a second, full mTLS connection — the same identities and pins as the control
connection (§1, `docs/planning/decisions.md` D-19) — opened on demand for the high-bandwidth,
latency-sensitive mirroring stream (F-3.3). It never substitutes weaker authentication for the
ticket defined here: the `mediaTicket` only binds an already fully authenticated media connection to
the control session that requested it, so an unauthenticated party, or a party authenticated as a
different peer, cannot hijack it (AC-08).

### Issuance

- `MediaTicketGrant { ticket, expiresAt }` (`control.proto`, E01-12) is sent over the `CONTROL`
  channel by the issuing side when a media connection is requested. The request message itself, and
  the rest of the mirror-session initiation flow, belong to Phase 6 (E60-01); this section
  normatively defines only the ticket's shape and its issuance/validation contract, which E60-01
  reuses without redefining.
- `ticket` MUST be exactly 32 bytes (256 bits), generated by a CSPRNG for every issuance. A receiver
  MUST reject a `MediaHello` (below) whose `ticket` field is any other length before comparing it to
  anything.
- `expiresAt` denotes the instant, milliseconds since the Unix epoch (UTC), 30 s after the moment of
  issuance. The issuer MUST record the 30 s deadline internally at issuance and MUST expire the
  ticket exactly 30 s after issuance regardless of what a receiver does with the wire-carried
  `expiresAt` value — the issuer is also the validator (the same Mac process), so it never trusts a
  wire-carried expiry against itself; the field exists only so the requesting side can avoid a doomed
  dial once its own copy of the deadline has passed.
- The issuer MUST record, alongside the ticket, the issuing control session's authenticated peer SPKI
  so validation can later check both the ticket value and the presenting peer's identity.

### Consumption and single use

- `MediaHello { ticket }` MUST be the first frame on the media connection (§3 already states this).
  Because a pinned peer's role on a newly accepted connection is otherwise ambiguous, the first frame
  itself is what distinguishes the two: a pinned-peer connection whose first frame is `MediaHello` is
  a media connection; one whose first frame is `VersionHello` (§6) is a control connection — both are
  accepted on the same single listener (`docs/planning/decisions.md` D-03).
- A `MediaHello` arriving on a **pairing-candidate** connection (§2 — a connection still inside the
  pairing window, not yet an ordinary authenticated peer) MUST be rejected as `UNKNOWN_PAYLOAD_TYPE`,
  closing with `MALFORMED_FRAME` (§3) — the same treatment as any other payload illegal for a
  connection's current state — without ever consulting the ticket table: pairing candidates are never
  eligible to open a media connection (`docs/planning/decisions.md` D-25).
- On an ordinary (already fully authenticated, non-pairing-candidate) connection, the validating side
  MUST validate a presented `ticket` in exactly this order, stopping at the first matching case
  (`docs/planning/decisions.md` D-65):

  0. **Absent or malformed.** `ticket` is absent, or present but not exactly 32 bytes → reject
     `MISSING`, before comparing it against anything held.
  1. **No match.** Compare `ticket`, in constant time, against every ticket this validator currently
     holds (§ Issuance, and Retention below — this includes tickets already consumed, expired but not
     yet purged, or bound to a since-ended session; nothing is excluded from this comparison set). If
     it matches none of them → reject `REUSED`.
  2. **Peer mismatch.** It matches a held ticket, but the connection presenting it is authenticated as
     a different peer than the SPKI the ticket was issued to → reject `OTHER_SESSION`, and — because a
     ticket presented by the wrong peer must be assumed to have leaked to that peer — permanently
     invalidate the matched ticket as a side effect, even though this presentation itself is rejected
     (see Invalidate-on-mismatch, below).
  3. **Session ended.** The peer matches, but the ticket's issuing control session has since ended →
     reject `OTHER_SESSION`.
  4. **Expired.** The session is still the issuing one, but 30 s have elapsed since issuance → reject
     `EXPIRED`.
  5. **Already consumed.** Not expired, but the ticket was already marked consumed by an earlier
     successful validation → reject `REUSED`.

  A presentation matching none of cases 0–5 is valid: the validating side MUST mark it consumed and
  bind the media connection to the ticket's issuing control session before accepting any further
  frame, in particular before accepting any media data.
- **Invalidate-on-mismatch.** Case 2 above (peer mismatch) is the only rejection case that
  additionally burns the ticket: once a ticket has been observed presented by a peer other than the
  one it was issued to, it MUST NOT be usable by *any* peer afterward, including the correct one — the
  mismatched presentation is itself evidence the ticket value is no longer secret. Cases 0 and 1 (an
  absent, malformed, or entirely unrecognized `ticket`) never burn anything, by construction: neither
  case has a held ticket record to act on, so a guess can never invalidate the real ticket it happened
  not to match. Cases 3, 4 and 5 need no additional invalidation step beyond what already applies: a
  ticket rejected for one of those reasons is already, respectively, unbindable (its session is gone),
  inherently one-shot-expired, or already consumed.
- Every ticket comparison — the constant-time search of case 1, and any other bytewise check —
  MUST use a constant-time comparison (invariant 6).

### Rejection

Every case in the ordered algorithm above closes the media connection with the close code
`TICKET_REJECTED` (§5, `#errors-and-close-codes`, row 6), using the local reason the matching case
names (`MISSING`, `REUSED`, `OTHER_SESSION`, or `EXPIRED`), and MUST NOT affect, close, or otherwise
degrade the control session that issued the ticket — the two connections are independent once
established.

The first frame on a media connection MUST arrive within 5 s of TLS completion (§10,
`#timeouts-connection-limits-and-resource-caps`, E01-22); exceeding that deadline closes the
connection with `PROTOCOL_TIMEOUT` (§5) rather than `TICKET_REJECTED`, since no `MediaHello` — and
therefore no ticket — was ever presented to reject.

### Handling requirements

- A ticket MUST NOT be logged, in full or in part, on either side, at any log level, in a debug or a
  release build (`docs/planning/decisions.md` D-25, invariant 7).
- A ticket MUST NOT be persisted to disk. **Retention.** A ticket record is retained in memory —
  marked consumed, session-ended, or invalidated-by-mismatch as each event occurs, rather than removed
  from the table — until exactly 30 s after its issuance, at which point the issuer MUST purge it.
  This is a deliberate departure from discarding a ticket the instant its session ends or it is
  consumed: retaining the (marked) record until every ticket's same absolute 30 s deadline is what
  lets the ordered algorithm above distinguish `REUSED` from `OTHER_SESSION` from `EXPIRED` precisely,
  instead of every one of those cases collapsing to "no match" (case 1) once the record is gone
  (`docs/planning/decisions.md` D-65). A ticket is never valid across a restart of either process and
  never valid for any control session other than the one that requested it — not even a later session
  between the same two peers.
- **One outstanding ticket per control session.** A control session has at most one currently valid
  (unconsumed, unexpired, not-yet-superseded) ticket outstanding at a time. If that session requests a
  new ticket while a previously issued one is still outstanding, the issuer MUST supersede the old one
  — treating it exactly as if consumed, so any later presentation of it is rejected `REUSED` — at the
  moment it issues the new one.
- **The requesting side's own deadline.** The requesting side (the phone, dialing the media
  connection) MUST compute its own deadline for a ticket as the instant it received the
  `MediaTicketGrant` plus 30 s, measured on its own monotonic clock — not by trusting the wire-carried
  `expiresAt` value, which reflects only the issuer's clock and does not account for delivery delay or
  clock skew between the two devices. `expiresAt` remains useful only as a record of the issuer's own
  30 s deadline (§ Issuance, above); the requesting side's decision to still attempt the dial MUST use
  its own measurement instead.

---
