# Tandem — open questions for the owner

Only decisions that change behaviour. Each has a recommended default that the backlog already
assumes; work proceeds on the default unless the owner overrides it. Answered questions move to
[`decisions.md`](decisions.md).

Q1–Q16 were answered on 2026-09-24 (owner accepted every recommended default) and are logged as
D-41 … D-56 in [`decisions.md`](decisions.md). Q19 was answered on 2026-10-04 and is logged as D-77.

| # | Question | Recommended default | Affects |
|---|---|---|---|
| Q17 | E22-07's pin-mismatch banner text ("`<peer>` presented an unexpected key") presupposes the Mac can name a peer whose current SPKI is *not* in the trust store. With trust bound to SPKI only (invariant 3) and the Mac never dialing (invariant 4), it cannot attribute an unrecognized key to a name without an IP/device-ID heuristic — which invites misattribution by an attacker. Should the named-peer branch be removed (always show the generic "An unpaired device..." text), or is a specific, invariant-3-safe attribution mechanism intended? | Remove the named-peer branch; always show the generic text for `pinMismatch` regardless of any locally-cached name, since the Mac has no invariant-3-safe way to attribute an unrecognized key to a specific paired device. | E22-07, E22-10 |
| Q18 | Scheduled key-rotation interval setting (E70-01, SPEC #key-rotation) offers Off / 90 / 180 / 365 days. Is that set and the default right? | Applied default: 365 days since the last rotation (or pairing); options Off, 90, 180, 365. | E70-01, E70-07 |
| Q20 | E20-03 found CompanionDeviceManager presence unusable for a Wi-Fi-only Mac (no-go). Should E20-16 (CDM association) be closed as won't-do? An association alone would add up to five new manifest permissions (`REQUEST_COMPANION_SELF_MANAGED`, `REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND`, `REQUEST_COMPANION_RUN_IN_BACKGROUND`, `REQUEST_COMPANION_USE_DATA_IN_BACKGROUND`, `REQUEST_OBSERVE_COMPANION_DEVICE_PRESENCE`) and a system consent dialog, for exemptions unrestricted battery already gives. | Close E20-16 as won't-do; add no companion permissions; PRD F-4.1 CDM wording to be updated. | E20-03, E20-16, E20-13 |
