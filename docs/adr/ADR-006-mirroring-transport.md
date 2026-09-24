# ADR-006: MediaProjection + Accessibility vs. ADB + scrcpy for mirroring/remote input

- **Status:** deferred to Phase 6
- **Date:** 2026-09-24
- **Issue:** E02-07

## Context

F-9.1–F-9.3 specify screen mirroring and remote input via `MediaProjection` /
`MediaCodec` capture and `AccessibilityService` input injection. F-9.4 records
an alternative — ADB wireless debugging with a bundled scrcpy-server (Apache
2.0) — that per PRD F-9.4 "gives better input injection and does not need
accessibility," at the cost of requiring developer mode. The backlog does not
wait for this ADR to build option (a): E61/E62 (`MediaProjection` +
`AccessibilityService`) are P0 v1 work regardless of this ADR's status;
E61-10 finalizes the ADR once E61-08's device measurements exist (E61-10
depends on E61-08), deciding whether (a) alone suffices for v1 or option (b)
(E62-10) is additionally authorized as P2.

## Options

**(a) `MediaProjection`/`MediaCodec` capture with `AccessibilityService` remote input**
- Pros: no developer mode required; matches invariant 8's user-started-session model directly — the accessibility session and its on-phone indicator are the same mechanism that authorizes input; no ADB dependency, no bundled third-party server.
- Cons: input injection fidelity is bounded by `dispatchGesture`/`performGlobalAction`/`ACTION_SET_TEXT` (F-9.3), which is coarser than raw input event injection.

**(b) ADB wireless debugging + bundled scrcpy-server (Apache 2.0)**
- Pros: better input injection fidelity (per PRD F-9.4: "gives better input injection and does not need accessibility").
- Cons: requires developer mode (a real setup cost and a security-posture change on the phone); uses a different input-authorization model than accessibility sessions, which must be independently checked against invariant 8 — a scrcpy-based path does not inherit the accessibility session's on-phone indicator for free; bundled third-party server adds supply-chain and licensing surface (Apache 2.0, compatible but must be tracked, cf. D-32).

## Decision

Not decided between (a) and (b) as the sole v1 mirroring path — that choice
is explicitly deferred to Phase 6 (PRD Phase 6 tasks: "decide ADR-006"),
finalized by E61-10. This does not block building (a): E61/E62 implement
`MediaProjection` + `AccessibilityService` as the v1 baseline in parallel.
Only option (b) (E62-10) is gated on this ADR's finalization. Whichever
option ends up authorized must satisfy invariant 8 independently — option
(b) does not inherit the accessibility session indicator for free and needs
its own on-phone, user-started-session indicator design if selected.

## Decision criteria (numeric thresholds for the Phase 6 decision)

1. **1080p ≥ 30 fps** and **< 120 ms** end-to-end latency on 5 GHz Wi-Fi (PRD targets; measured by E61-08).
2. Input-injection success rate on the device matrix, per E62-09's manual thresholds: 20 of 20 taps within 10 px of the target center in both portrait and landscape, 10 of 10 swipes scroll in the dragged direction, a 50-character string round-trips exactly, and BACK/HOME/RECENTS each take effect within 1 s (5 of 5 each).
3. Developer mode required: yes/no.
4. Licence compatible: yes/no (scrcpy-server is Apache 2.0; track under D-32 supply-chain gate if chosen).

## Consequences

- (a) is implemented in E61/E62 as the v1 baseline; F-9.4/(b) (E62-10) stays
  gated; E61-10 decides whether (a) alone suffices for v1 or (b) is
  additionally authorized as P2.
- Traceability (`E61-10`) is the issue that finalizes this decision using
  the criteria above; `E62-10` (input path) depends on `E61-10`'s outcome.

## Revisit criteria: criteria 1–2 measured, 3–4 answered

This is not an "Accepted" ADR with a revisit trigger — it is itself the
placeholder pending E61-10's finalization. Finalize when criteria 1–2 are
measured for (a) via E61-08 (fps/latency) and E62-09 (input-injection
thresholds); criteria 3–4 for (b) — developer mode requirement and licence
compatibility — are answered on paper, since neither needs a device
measurement.

## Links

- Backlog: E02-07 (`docs/planning/backlog/phase-0.yaml`); E61-08, E61-10, E62-09, E62-10 (`docs/planning/backlog/phase-6.yaml`)
- PRD: F-9.1–F-9.4, Phase 6 tasks ("decide ADR-006"), `<risks>` (MediaProjection consent per session → optional ADB/scrcpy path)
- Invariant 8; use cases UC-22, UC-23; abuse case AC-06
- Traceability: `docs/planning/traceability.md` rows for F-9.4, AC-06, UC-22, UC-23, invariant 8
