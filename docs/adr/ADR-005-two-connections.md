# ADR-005: Two connections (control + media) vs. one multiplexed connection

- **Status:** Accepted
- **Date:** 2026-09-24
- **Issue:** E02-06

## Context

Screen mirroring (F-9.1) puts high-bandwidth, latency-sensitive H.264 frames
on the wire alongside low-latency control traffic (notifications, clipboard,
heartbeats). F-3.2 already gives every channel credit-based flow control so
a large transfer cannot starve notifications on a single connection; the
question is whether that is sufficient on its own or whether media also
needs a physically separate mTLS connection.

## Options

**(a) Separate control and media mTLS connections, media bound to control via a single-use ticket (F-3.3)**
- Pros: a large in-flight H.264 frame on the media connection cannot head-of-line-block a TLS record boundary on the control connection, regardless of flow-control tuning; the media connection is opened only on demand (mirroring is not always active) and closes with the session; the `mediaTicket` (F-3.3: single-use, 30 s expiry; E60-08 issuer/validator) binds it to a specific control session without needing a second identity.
- Cons: a second acceptor on the same listener (E60-03, D-03) and a ticket-issuance protocol (`MediaHello`, D-25) add implementation and test surface beyond a single connection.

**(b) One multiplexed connection for everything, relying solely on channel-level flow control (F-3.2)**
- Pros: one connection, one handshake, no ticket protocol.
- Cons: TLS records and TCP segments for a large in-flight video frame still occupy the wire ahead of a queued control frame at the transport level; channel-level credit accounting happens above that layer, so it cannot fully prevent head-of-line blocking on the shared socket — a real risk given the 1 MiB max frame size and CBR video profile (F-9.1).

## Decision

Option (a): two connections, media bound to control by a single-use ticket
(F-3.3). D-03 keeps both on the same single Mac listener port (ADR-002)
rather than a separate media port.

## Consequences

- F-3.2's credit-based flow control is still required even with two
  connections: it is what prevents one control channel (e.g. FILES) from
  starving another (e.g. NOTIFY) on the control connection itself. The two
  mechanisms are complementary, not alternatives — (a) solves head-of-line
  blocking *between* control and media; F-3.2 solves it *within* control.
- Adds the `MediaHello` / `mediaTicket` issuance protocol (D-25) and its own
  failure modes (ticket reuse, deadline miss, MediaHello on a pairing
  candidate — all rejected) as implementation and test surface.
- Both connections share the same peer identities and pins as the control
  connection (F-3.3); no separate trust anchor is introduced.

## Revisit criteria

Revisit in Phase 6 if measured data shows a single multiplexed connection is
sufficient: specifically, if a single multiplexed connection kept
control-message latency **p95 < 100 ms** while streaming 1080p30 on 5 GHz
Wi-Fi, and mirroring still met **< 120 ms** end-to-end latency, option (b) is
reconsidered. No such measurement exists in the backlog today; producing it
would need a multiplexed variant of E61-08's mirroring performance harness
(control and media routed over one connection instead of two) — a new issue,
not part of this ADR's acceptance.

## Links

- Backlog: E02-06 (`docs/planning/backlog/phase-0.yaml`)
- PRD: F-3.2 (framing and flow control), F-3.3 (media connection), F-9.1 (capture and encode)
- Decisions: D-03 (single listener port for both connections), D-25 (media ticket rules)
- Invariant 1; use case UC-22
