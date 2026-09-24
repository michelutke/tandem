# ADR-002: Phone as TLS client, Mac as the sole listening server

- **Status:** Accepted
- **Date:** 2026-09-24
- **Issue:** E02-03

## Context

Invariant 4 requires the Android app to open no listening sockets. Android
has no reliable way to keep a listening socket alive across Doze and OEM
battery killers, and a listening service on a phone is the kind of thing
store-adjacent scanners flag. A single well-known Mac port is easier to
firewall and to audit externally (`nmap`). Appendix C open question 3 asks
whether the Mac should also be able to *initiate* reconnects (e.g. via a
Bluetooth LE hint) — any answer to that question must not require the phone
to listen.

## Options

**(a) Phone always dials; Mac is the only listener (single port)**
- Pros: satisfies invariant 4 directly; one well-known, auditable listener; no reliance on Android's unreliable background listening; a Mac-initiated reconnect can still be modeled as a hint that makes the phone dial sooner (D-08), never a phone listener.
- Cons: the Mac cannot push a connection open; all reconnect logic lives on the phone (F-3.4).

**(b) Both sides can listen**
- Pros: either side can initiate.
- Cons: violates invariant 4 outright; Android listening sockets do not survive Doze/OEM kills reliably and would need a foreground-visible open port, defeating the "no listening service" property this invariant protects.

**(c) Phone listens, Mac dials**
- Pros: none identified over (a) for this app's threat model.
- Cons: same invariant-4 violation as (b); additionally the Mac (not the phone) is the device expected to be reachable at a stable local address, so this inverts the natural reachability assumption.

## Decision

Option (a): the phone always dials; the Mac is the sole listener on a single
port (D-03: also used for the second, media mTLS connection — no separate
media port).

## Consequences

- Directly implements invariant 4 (Android opens no listening sockets).
- Constrains (does not resolve) Appendix C open question 3: a Mac-initiated
  reconnect (if ever built) can only be a *hint* that makes the phone dial
  sooner — never a phone listener. E20-13 (Mac-initiated reconnect hint ADR,
  Appendix C.3) is what actually resolves the question; it depends on this
  ADR (E02-03) and is itself gated on measured reconnect data from E20-12.
- All reconnect strategy (last-working address → Bonjour → pairing
  addresses, backoff) lives on the phone (F-3.4); the Mac never needs
  outbound-dial logic for the control or media connection.

## Revisit criteria

Numeric go/no-go this decision relies on:
1. Phone-dialed reconnect **< 5 s p95** after a network change or Mac wake
   (UC-04), measured by E15-12 / E20-12.
2. `nmap -p-` against the phone shows **0 open TCP ports** outside E15-12's
   allowlist; **0 LISTEN sockets** owned by the Tandem uid.

Revisit if the E20-12 overnight Doze gate fails: specifically, if reconnect
does not happen within **5 s of the next Doze maintenance window or
screen-on** (E20-12) — not a p95 figure, since Doze wake timing is bucketed
by maintenance windows rather than continuously distributed — without some
Mac-initiated wake signal that would require rethinking the listener model.

## Links

- Backlog: E02-03 (`docs/planning/backlog/phase-0.yaml`); E20-13 (`docs/planning/backlog/phase-2.yaml`)
- Invariant 4; PRD F-3.1, F-3.4, Appendix C open question 3
- Decisions: D-03 (media on same single listener port), D-08 (Mac-initiated reconnect hint resolved by E20-13, no phone listener in any option)
- Traceability: `docs/planning/traceability.md` row for invariant 4 (E12-04, E00-14, E02-03, E20-13 → E15-12, E71-08, E71-09)
- Use case: AC-04
