# ADR-008: Manual pairing uses a commit-then-reveal SAS, never a fingerprint prefix

- **Status:** Accepted
- **Date:** 2026-10-02
- **Issue:** E73-01

## Context

PRD F-2.2 (manual pairing for camera-less setups) is deferred to v2+ and, per ADR-004, may only be
built with a hash-commitment short authentication string (SAS) meeting a numeric floor: at least 6
decimal digits, online guess probability at most 3 in 10^6 within a 3-attempt window. This ADR
specifies that scheme so E73-02 (protocol), E73-03/E73-04 (implementation) and E73-05 (mitm-lab) can
be built against it.

QR pairing (F-2.1, SPEC §2) authenticates the Mac key optically (`fp`) and proves possession of a
16-byte single-use secret (`s`). Manual pairing has neither: both sides start as unauthenticated
strangers over a mutual-TLS connection whose peer SPKIs are not yet pinned (invariant 3). The only
authenticator is a human comparing a short code on two screens, so the code must resist an attacker
who relays between the two devices and who can choose his own keys and nonces.

The reference app's manual path compares a 32-bit fingerprint prefix (PRD Appendix A), which an
attacker can grind offline by generating keys until a prefix collides. That design is rejected
outright below.

## Options

**(a) Commit-then-reveal SAS bound to both SPKIs and the TLS channel**
- Pros: no secret needs to be transported; the attacker has exactly one online guess per attempt
  (10^-6 for 6 digits); no offline grinding is possible; reuses the existing pairing window and
  confirmation UX.
- Cons: relies on the owner actually comparing the two screens; adds extra round trips.

**(b) Fingerprint-prefix comparison (what LinkMyMac does)**
- Pros: trivially simple.
- Cons: rejected, see Decision.

**(c) Typed shared secret (Mac shows a code, owner types it on the phone)**
- Pros: no commitment protocol.
- Cons: a short typed secret is an online-guessable password with no transcript binding, and it
  invites a second, differently-hardened pairing path; out of scope for F-2.2 as written.

## Decision

Option (a). Manual pairing is an additional pairing method that never replaces or weakens QR
pairing. A fingerprint prefix, or any other truncation of a fingerprint, is never an input to, a
substitute for, or a fallback from the SAS check (PRD ADR-004; ADR-004 above).

### Roles and window

- Manual pairing reuses the UC-03 pairing window unchanged (SPEC §2 Pairing window): 120 s expiry,
  at most 3 attempts, one pairing-candidate connection at a time (D-18), attempts burned the same
  way (D-70), window closed on success, expiry or exhaustion. No separate timer or attempt budget is
  introduced.
- The Mac opens the window in *manual mode* on an explicit owner action and the phone enters manual
  mode on an explicit owner action. The mode is fixed when the window opens; a QR window accepts
  only the QR sequence and a manual window accepts only the manual sequence (see Downgrade).
- The phone is the TLS client and the Mac the server (ADR-002); the Mac's address comes from the
  owner or from discovery and is never a trust anchor (invariant 3).
- Both sides run the VersionHello exchange and the Mac sends `PairChallenge` first, so `cb` is
  available as in SPEC §1/§2. Manual pairing uses the same `cb` and the same 10 s first-message
  deadline.

### Scheme

Notation: `LP(x) = u16be(len(x)) || x`; `||` is concatenation; `macSpkiDer` and `phoneSpkiDer` are
the 91-byte P-256 SPKI DER taken from the certificates actually presented on this TLS handshake
(never from a message body); `cb` is this session's channel-binding value (SPEC §1).

1. Each side draws a 16-byte nonce from a CSPRNG: `nonceP` (phone), `nonceM` (Mac).
2. `ctx = ASCII("tandem-manual-pair-v1") || LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb)`.
3. Commit: each side computes
   `commitX = SHA-256(ASCII("tandem-manual-commit-v1") || roleByte || nonceX || ctx)` with
   `roleByte = 0x01` (phone) or `0x02` (Mac), and sends `Commitment { hash = commitX }`. The phone
   sends first, then the Mac.
4. A side MUST NOT send its `Reveal` until it has received the peer's `Commitment`. Phone then sends
   `Reveal { nonce = nonceP }`; the Mac verifies it against `commitP` (recomputing with its own
   observed SPKIs and `cb`) in constant time and only then sends `Reveal { nonce = nonceM }`, which
   the phone verifies against `commitM` the same way. Any mismatch, missing, duplicate or
   out-of-order message aborts with `PAIRING_FAILED` and burns one attempt. Reveal before the peer's
   Commitment is such an out-of-order message.
5. Both sides compute
   `h = HMAC-SHA256(key = nonceP || nonceM, msg = ASCII("tandem-manual-pair-v1") || ctx)` and
   `sas = (u64be(first 8 bytes of h)) mod 1000000`, rendered zero-padded to exactly 6 digits and
   grouped `000 000` on both screens.
6. Confirmation follows the existing QR flow (SPEC § Mutual confirmation, D-16): the Mac shows the
   SAS, the sanitized phone name and Pair / Don't Pair (default and Escape map to Don't Pair);
   `ManualPairResult { accepted }` is sent only after the owner clicks Pair; the phone shows the same
   SAS and commits the Mac's SPKI pin only after both receiving `ManualPairResult` accepted and the
   owner tapping "Codes match" (same Revoke-on-cancel/timeout behaviour). The owner reporting a
   mismatch on either screen is terminal for the window, like an owner decline (D-16): abort without
   pinning, send `PairRejected { REJECTED_BY_OWNER }` / `Revoke` as in SPEC, destroy the nonces and
   close the window, rather than burning one attempt and leaving it open.

Two deliberate refinements of the E73-01 sketch, both strictly stronger: the HMAC message carries
`ctx` (so the SAS itself differs whenever the SPKI pair or `cb` differs), and the SAS reduces 64
bits rather than 32 so the modulo bias is about 2^-44 instead of about 8 x 10^-6 relative (a 32-bit
reduction would push 3 attempts to marginally above the 3 x 10^-6 floor).

### Security properties

- **Commit-then-reveal.** Neither nonce is revealed until both commitments have been sent, so an
  active attacker must fix the nonces it uses toward each side before it learns either real nonce.
  Commitments are hiding (128-bit random nonce inside SHA-256) and binding (collision resistance),
  so there is nothing to grind offline.
- **SPKI binding.** `ctx` contains both handshake SPKIs, so a relay (which must terminate TLS with
  its own key on at least one side, enforced by `CertificateVerify`, SPEC §1) produces a different
  `ctx` per leg. A commitment forwarded from one leg fails verification on the other, forcing the
  attacker to commit to fresh nonces on both legs. The SAS shown on the phone is then a function of
  an independent uniform real nonce, and likewise for the Mac, so the two codes agree only by chance.
- **Attacker success probability.** Per attempt the two codes are independent and uniform over
  10^6 values (bias about 2^-44), so a relay is undetected with probability 10^-6 per attempt and at
  most 3 x 10^-6 over the 3-attempt window, which meets the ADR-004 floor. A relay attempt that
  reaches the compare step is visible to the owner as a code mismatch, and a reported mismatch
  closes the window, so in practice the attacker gets one SAS guess; attempts that fail earlier
  (bad Commitment/Reveal, wrong payload) burn one attempt each. There is no offline attack and no
  way to retry beyond the window.
- **Replay.** Fresh 16-byte nonces per attempt plus `cb` (fresh per connection, SPEC §1) in `ctx`
  mean a recorded Commitment/Reveal pair cannot be accepted on another connection or attempt.
  Nonces and commitments are discarded when the attempt ends; they are never reused.
- **Single use and expiry.** There is no long-lived secret. The window is single-use (success
  closes it), expires after 120 s, and the nonces live only for one attempt (invariant 6).
  Commitment and Reveal comparisons are constant time. Nonces and the SAS are never logged
  (invariant 7).
- **Residual risk.** Unlike QR, the window is attackable by any LAN peer that connects before the
  owner's phone; such a peer can burn attempts (a DoS already accepted for QR windows, D-70) and
  can prompt a Pair dialog, but the owner then sees a device name and SAS with no matching code on
  their own phone and declines. A human who clicks through without comparing defeats the scheme;
  that is inherent to SAS pairing and is why the compare step is explicit.

### Downgrade resistance

- No capability negotiation, and no silent fallback. A failed or unavailable QR pairing never
  switches to manual; the owner must start manual mode explicitly on both devices.
- The window mode is fixed at open. A manual-sequence message on a QR window, or a QR
  `PairRequest` on a manual window, is a wrong payload: `PAIRING_FAILED`, one attempt burned.
- The phone MUST NOT accept a manual pairing where the owner expected QR (or the reverse) without a
  visible mode label; there is no mode that skips the SAS, and the pin is committed only after the
  SAS is confirmed.
- The label strings (`tandem-manual-pair-v1`, `tandem-manual-commit-v1`) are distinct from the QR
  labels (`tandem-pair-v1`, `tandem-pair-code-v1`), so no value computed in one method can be
  replayed in the other. A future version change bumps the `-v1` suffix; protocol version mismatch
  fails closed (invariant 5).

### Compare-step UX

- The SAS is the only thing the owner is asked to compare, shown large, zero-padded and grouped
  (`042 117`), identically on both screens, with the peer's sanitized device name beside it.
- Default actions are the safe ones: Don't Pair on the Mac, Cancel on the phone; "Codes match" is
  never a default button and is not enabled until the code is visible. Mismatch is a first-class,
  one-tap path ("Codes differ") that aborts without pinning.
- Copy states what a mismatch means (possible interception) and that pairing must be restarted
  from scratch (a new window) after a mismatch. Strings and states follow `docs/design/ui-spec.md`; no new tokens.
- Fingerprints, even full ones, are not offered as an alternative comparison in this flow; an
  "advanced" fingerprint view for manual pairing is out of scope.

### Rejection of fingerprint-prefix comparison

A fingerprint prefix, however long it is made short enough to compare by eye, is rejected for any
version. An attacker can generate key pairs offline until the first N bits of its SPKI hash match
the victim's, at a cost of about 2^N hashes, which is cheap for the 32 bits used by the reference
app and still cheap for any prefix a human will read. The SAS above has no offline-grindable
component because both nonces are fixed by commitments before either is revealed. Neither client
may contain a code path that compares fingerprints or prefixes as a substitute for the SAS
(tested in E73-03).

## Consequences

- E73-02 defines `Commitment { hash }`, `Reveal { nonce }`, `ManualPairResult { accepted }` and the
  vectors for this scheme: a known nonce pair plus SPKIs plus `cb` yields a fixed 6-digit SAS, and a
  Reveal not matching its Commitment fails verification.
- E73-03/E73-04 implement the state machine, including Reveal-before-Commitment abort, and run
  inside the existing pairing window; SPEC §2 and QR pairing (E14) are unchanged. SPEC.md will need
  a manual-pairing subsection when E73-02 lands, not before.
- E73-05 mitm-lab covers brute force (more than 3 attempts, commitment guessing) and downgrade
  (QR window fed manual messages and vice versa); both must fail closed.
- Revisit criteria from ADR-004 stand: SAS of at least 6 digits and at most 3 x 10^-6 online guess
  probability per window may not be relaxed.

## Links

- Backlog: E73-01 (`docs/planning/backlog/phase-7.yaml`); gates E73-02, E73-03, E73-04, E73-05
- PRD: F-2.2 (manual pairing, v2+), F-2.1, Appendix A; ADR-004 (`ADR-004-qr-only-pairing.md`)
- SPEC: §1 channel binding, §2 pairing window, frame order, confirmation code, mutual confirmation
- Decisions: D-16, D-18, D-41, D-70
- Invariants: 3 (SPKI-only trust), 5 (fail closed), 6 (single-use, constant-time, expiring), 7 (no
  secrets in logs)
- Use cases / abuse cases: UC-03, AC-03, AC-20
