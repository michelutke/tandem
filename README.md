# Tandem

Secure Android ↔ macOS companion: notifications, clipboard, files, photos, SMS, contacts,
calls, and screen mirroring with remote input — over mutually authenticated TLS 1.3 with
keys pinned at QR pairing. No plaintext paths, no fallbacks, no listening sockets on the phone.

> Status: **planning**. No code yet. See [`docs/planning/`](docs/planning/README.md).

## Repository layout (monorepo)

```
docs/        PRD, protocol spec, threat model, ADRs, planning backlog
protocol/    .proto schema (single source of truth) + cross-platform test vectors
android/     Kotlin / Compose app, core/* and feature/* Gradle modules
macos/       Swift 6 menu bar app, Share extension, local SwiftPM packages
tools/       conformance, pcap-audit, mitm-lab, fuzz, planning scripts
```

## Documents

- [PRD](docs/PRD.md) — requirements, architecture, security invariants
- [Use cases](docs/planning/use-cases.md) — UC-xx and abuse cases AC-xx
- [Roadmap](docs/planning/roadmap.md) — phases, exit checklists, epic graph
- [Backlog](docs/planning/BACKLOG.md) — generated overview of all epics and issues

## Planning workflow

```sh
ruby tools/planning/sync_issues.rb validate   # schema, references, dependency cycles
ruby tools/planning/sync_issues.rb render     # regenerate docs/planning/BACKLOG.md
ruby tools/planning/sync_issues.rb sync       # push epics/issues/milestones/labels to GitHub
```

Setup, configuration, deployment, and architecture sections will be filled in by E00
(scaffolding) as the code lands.
