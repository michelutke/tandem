# ADR-004: QR-only pairing for v1; manual pairing only with a commitment-based SAS

- **Status:** Accepted
- **Date:** 2026-09-24
- **Issue:** E02-05

## Context

The v1 target user is a single owner pairing their own phone and Mac, and
both devices have a camera available (F-2.1). The reference app LinkMyMac's
manual pairing path compares only a 32-bit fingerprint prefix (PRD Appendix
A: "Manual pairing compares only a 32-bit fingerprint prefix → ADR-004"),
which is brute-forceable and is exactly the class of bug this ADR must not
reintroduce.

## Options

**(a) QR-only pairing in v1; manual/no-camera pairing deferred to v2+, and only ever implemented with a hash-commitment SAS**
- Pros: QR pairing (F-2.1) already carries the full 256-bit fingerprint and a per-window secret optically, with no operator-comparable short code to brute-force; not needed for the v1 target user (single owner, has a phone camera); if a manual path is ever added, a hash-commitment short authentication string (SAS, ≥ 6 digits, compared on both screens after both sides commit) cannot be attacked the way a fingerprint-prefix check can.
- Cons: no camera-less pairing path in v1.

**(b) Support a fingerprint-prefix manual fallback in v1 for camera-less setups**
- Pros: covers camera-less setups without waiting for v2.
- Cons: a short fingerprint prefix has too few bits to resist online guessing and is the documented LinkMyMac weakness this project explicitly avoids (clean-room rule; Appendix A gap list); would need its own commitment scheme to be safe, which is the same work as deferring to v2 while still shipping the risk sooner.

## Decision

Option (a): QR-only pairing for v1. Manual/no-camera pairing is deferred to
v2+ (PRD F-2.2) and, if ever built, may only use a hash-commitment SAS. A
fingerprint-prefix manual pairing design is explicitly ruled out for any
version.

## Consequences

- F-2.2 (manual pairing) stays out of scope until v2+ and requires its own
  ADR before implementation (per PRD F-2.2: "Must go through a separate ADR
  before implementation").
- QR pairing (F-2.1) remains the only v1 pairing method; its confirmation
  step (D-16: 6-digit confirmation code, Mac default "Don't Pair") is the
  evil-QR defense (AC-20), not a substitute for a manual-pairing SAS.
- Any future manual-pairing ADR must specify a hash-commitment SAS meeting
  the numeric floor below; a fingerprint-prefix check is rejected outright,
  citing the LinkMyMac 32-bit prefix finding as the negative example this
  project's clean-room rule and threat model exist to avoid.

## Revisit criteria

Numeric floor for any future manual pairing design: a hash-commitment SAS of
**≥ 6 decimal digits**, giving an online guess probability **≤ 3 in 10^6**
within a 3-attempt window — never a fingerprint prefix. A future ADR may
revisit whether to build manual pairing at all (v2+ scope), but may not
relax this floor.

## Links

- Backlog: E02-05 (`docs/planning/backlog/phase-0.yaml`)
- PRD: F-2.1 (QR pairing), F-2.2 (manual pairing, deferred), Appendix A (LinkMyMac 32-bit prefix finding)
- Decisions: D-16 (6-digit confirmation code, evil-QR defense), D-41 (owner keep decision on the confirmation tap)
- Invariants: 3 (trust bound to SPKI fingerprints only), 6 (secrets constant-time, single-use, expiring)
- Use cases / abuse cases: UC-03, AC-03
- Future manual pairing (v2+, gated on this floor): E73-01 (ADR), E73-02 (protocol), E73-03/E73-04 (implementation), E73-05 (mitm-lab brute-force/downgrade scenarios)
