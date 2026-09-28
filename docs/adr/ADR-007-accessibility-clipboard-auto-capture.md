# ADR-007: Accessibility-based clipboard auto-capture ships off by default, opt-in only

- **Status:** Accepted
- **Date:** 2026-09-28
- **Issue:** E31-09

## Context

F-6.2 (Android → Mac clipboard) needs a way to notice when the user copies text on the phone.
Android 10+ blocks background clipboard reads for apps not in the foreground, so v1's explicit
entry points — share sheet target and `PROCESS_TEXT` (E31-06), foreground-app capture while
Tandem itself is frontmost (E31-07), and a Quick Settings tile (E31-12) — cover the cases where
the user takes an explicit action or Tandem is already visible. None of them notice a copy made
inside some other app that the user never explicitly sent.

An `AccessibilityService` can observe `TYPE_VIEW_TEXT_CHANGED`/window-content-changed events
system-wide and read the clipboard whenever it changes, regardless of which app is foreground —
closing that gap without any user action per copy. The PRD's risk table already flags this
directly: "Accessibility service is a high-privilege surface" / "Abuse if the transport is
compromised," mitigated by invariant 8 (remote input only in a user-started mirror session with an
on-phone indicator) and "minimal accessibility config." That mitigation is scoped to *input*
injection (F-9.x remote control); clipboard auto-capture is a different feature that would use the
same OS permission for a different purpose, and needs its own decision.

## Options

**(a) Ship accessibility-based auto-capture on by default (or as a suggested/nudged setup step)**
- Pros: closes the only real gap in Android → Mac clipboard capture; best user-visible experience,
  works transparently from any app.
- Cons: `AccessibilityService` is one of the most sensitive permissions Android exposes — it can
  read screen content and text across every other app on the device, not just clipboard changes.
  Granting it by default (or nudging most users into granting it) maximizes the app's exposure to
  that permission for every user, including the large majority who would be fine with the explicit
  entry points alone. If the transport or the app itself is ever compromised, an
  already-granted accessibility permission is a bigger blast radius than one the user never
  granted. Store review and OEM scrutiny of accessibility usage is also stricter for apps that
  request it without an obvious, narrow, user-facing reason.

**(b) Ship accessibility-based auto-capture off by default, opt-in only — chosen**
- Pros: the sensitive permission is only ever active for users who explicitly asked for the
  convenience and were told what it means; every other user's exposure is limited to the explicit
  entry points (E31-06/E31-07/E31-12), none of which need this permission at all. Matches the PRD's
  own existing risk-table language ("accessibility capture only as documented opt-in") and F-6.2's
  spec text almost verbatim.
- Cons: users who never discover or enable the opt-in still hit the background-clipboard-read gap
  for clipboard changes made outside Tandem and outside a share/tile/`PROCESS_TEXT` action.

**(c) Don't build accessibility-based capture at all**
- Pros: zero exposure to the permission; simplest to reason about and audit.
- Cons: throws away a real, requested capability (F-6.2 lists it explicitly) for no security gain
  over (b), since (b) already keeps exposure at zero for every user who doesn't opt in.

## Decision

Option (b): build accessibility-based clipboard auto-capture, but ship it off by default as a
documented, explicit opt-in setting, never enabled by a first-run nudge or bundled with another
permission request. The setting's own explanation must state plainly what the permission can see
(all on-screen text, not just clipboard) before the user grants it, not just what Tandem uses it
for.

Rationale: this only affects the small number of users who need it enough to seek it out and
accept the trade-off explicitly; it doesn't create a new source of exposure for the rest of the
user base, and it doesn't change invariant 8's scope (that invariant already governs *input*
injection during mirror sessions specifically, not clipboard reads — this ADR does not touch
invariant 8's own audit).

## Consequences

- E31-13 and friends (the explicit entry points) ship first and are the default experience;
  accessibility auto-capture is a strictly additive, separately-gated feature on top, never a
  substitute a user is steered toward.
- The settings surface presenting this opt-in (backlog TBD, likely part of E20-19's Android
  settings tab) must show the permission's real scope, not a euphemism, before requesting it.
- The security audit suite (`tools/security/`) should treat this permission's grant state as
  something to observe (present/absent), not something to assume absent — a future device-matrix
  or log-audit pass should confirm no clipboard content is ever logged regardless of which capture
  path produced it (invariant 7 already covers this generally).
- Loop/size guards (F-6.3: origin tag + content hash, 1 MiB cap) apply identically regardless of
  which of the four entry points produced the clip — this ADR doesn't introduce a second code path
  for that logic, only a second *trigger* for the same one.

## Revisit criteria

Reopen this ADR if either becomes true:
1. Android introduces a narrower, purpose-built API for background clipboard-change notification
   that doesn't require the full `AccessibilityService` surface (there is no such API today).
2. Real-world opt-in rates turn out near-universal in practice (e.g. onboarding data shows most
   users enable it anyway), suggesting the off-by-default framing should become a first-run
   suggested step rather than a buried settings toggle — still opt-in, but more visible.

## Links

- Backlog: E31-09 (`docs/planning/backlog/phase-3.yaml`); related: E31-06, E31-07, E31-12, E31-13
- PRD: F-6.2 (Android → Mac clipboard); risk table row "Android background clipboard restrictions"
  and "Accessibility service is a high-privilege surface"
- Invariants: invariant 7 (no secrets/clipboard content in release logs), invariant 8 (remote input
  scope — related permission, different feature, not touched by this ADR)
