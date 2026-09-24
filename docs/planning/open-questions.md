# Tandem — open questions for the owner

Only decisions that change behaviour. Each has a recommended default that the backlog already
assumes; work proceeds on the default unless the owner overrides it. Answered questions move to
[`decisions.md`](decisions.md).

| # | Question | Recommended default | Affects |
|---|---|---|---|
| Q1 | Keep the extra "Codes match" tap on the phone even though it adds a human step to the PRD "< 10 s pairing" target? | Keep the tap (evil-QR defence, D-16); measure < 10 s from scan to code shown, excluding the owner's tap. | E14-05, E14-16, E14-18, UC-03 |
| Q2 | Update PRD text (F-1.3, F-2.1, F-3.4, stack line) or keep changes in SPEC + `decisions.md` only? | SPEC + `decisions.md` only (D-40); optionally one PRD errata line pointing to `decisions.md`. | PRD, E01-01, E01-02, E70-01 |
| Q3 | If ML Kit's zero egress cannot be proven, switch the QR decoder to zxing-cpp? | Yes, zxing-cpp. | E14-23, E14-10, E00-29, E71-14 |
| Q4 | Feature caps: files ≤ 64 GiB, ≤ 4 pending offers, ≤ 2 active per direction, auto-accept only ≤ 1 GiB (setting); SMS ≤ 1600 chars, ≤ 10 sends / min. OK? | Keep; auto-accept setting off by default. | E01-22, E40-07, E40-18, E50-04 |
| Q5 | Disconnected-phone notification buffer: memory only, ≤ 50 entries, ≤ 60 s, drop oldest. OK? | Keep (nothing persisted on the phone). | E30-01, E30-16 |
| Q6 | Heartbeat: Mac sends after 15 s idle, declares dead after 45 s; phone never wakes itself in Doze. OK? | Keep; revisit only if the E20-12 overnight gate fails. | E01-07, E20-05, E20-15, E20-12 |
| Q7 | Fuzz budgets: 5 min per parser target on PRs touching parsers; 24 h per target before release. OK? | Keep. | E15-13, E15-14, E71-01 … E71-04, E71-13 |
| Q8 | Spike go thresholds: handshake p95 ≤ 1000 ms (StrongBox) / ≤ 300 ms (TEE), 10/10 and 20/20 runs, every matrix device must pass. OK? | Keep; a StrongBox device that fails only on latency may go TEE-only rather than fail ADR-003. | E03-03, E03-04, E02-04, E10-01 |
| Q9 | Mac SMS / contacts stores without app-level encryption (0600, backup-excluded, FileVault assumed). OK? | Keep for v1 (D-12). | E50-09, E51-04 |
| Q10 | Per-app notification filter on the phone only, no list on the Mac in v1. OK? | Keep (D-04). | E30-04, E30-15 |
| Q11 | Show Wi-Fi signal strength in the Mac status, or only network type + cellular level? | Network type + cellular level only. | E23-02, E23-04 |
| Q12 | v1 SMS text only (MMS v2, RCS never), confirmed by the real message-mix spike? | Text only unless E50-12 shows > 10 % MMS in the owner's threads. | E50-12, E50-01, E50-07 |
| Q13 | Restart the phone service after an app update (MY_PACKAGE_REPLACED), not only after reboot? | Yes (already in E20-08). | E20-08 |
| Q14 | Mac key rotation with several phones: after 7 days of waiting, "Finish" unpairs phones that have not confirmed. Acceptable? | Yes (D-34); the Mac never switches keys silently. | E70-03, E70-11, E70-13 |
