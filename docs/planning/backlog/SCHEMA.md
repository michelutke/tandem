# Backlog YAML schema

One file per phase: `phase-0.yaml` … `phase-7.yaml`. Each file is a list of epics.

```yaml
phase: 1
epics:
  - id: E12
    title: Secure transport (mTLS 1.3 client/server, pinning)
    labels: [area:transport]          # extra labels; type:epic + phase are added automatically
    prd: [F-3.1]
    use_cases: [UC-03, UC-05, AC-01, AC-04]
    summary: |
      Why this epic exists and what "done" means in one paragraph.
    scope:
      - In-scope bullet
    out_of_scope:
      - Explicitly excluded bullet (with pointer to the epic/phase that owns it)
    exit_criteria:                    # epic-level checklist, testable
      - macOS listener rejects TLS 1.2 (openssl s_client -tls1_2 fails)
    issues:
      - id: E12-01
        title: "[macos] NWListener with TLS 1.3-only mTLS options"
        type: task                    # story | task | spike | adr | test | doc
        platforms: [macos]            # android | macos | protocol | tools | docs | ci
        priority: P0                  # P0 | P1 | P2
        size: M                       # S | M | L
        prd: [F-3.1]
        use_cases: [UC-03]
        invariants: [1, 2, 5]         # PRD security invariants touched (1–8), [] if none
        depends_on: [E10-02, E11-03]  # issue IDs from any phase file; [] if none
        description: |
          What to build and key design notes. Reference SPEC.md sections, ADRs, APIs.
        acceptance:
          - Observable, testable criterion
        tdd:
          - listener_tls12ClientHello_handshakeFails
          - listener_unknownClientCertOutsidePairingWindow_rejected
        notes: |                      # optional: risks, open questions, links
```

Rules:
- Valid YAML (quote titles containing `:` or `[`). Use `|` block scalars for prose.
- `depends_on` must reference existing issue IDs. No cycles.
- Split per platform when Android and macOS work are independent; use `[cross]` only for
  work that must land together (e.g. end-to-end tests).
- `tdd` entries are concrete test names (unit, conformance, integration, instrumented). For
  `spike`/`adr`/`doc` use `tdd: []` and put the deliverable in `acceptance`.
