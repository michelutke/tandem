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
        tdd:                          # "layer: unit_condition_expectedResult", quoted
          - "unit: verifyBlock_unknownCertOutsidePairingWindow_rejected"
          - "integration: listener_tls12ClientHello_handshakeFails"
        notes: |                      # optional: risks, open questions, links
```

Rules:
- Valid YAML (quote titles containing `:` or `[`). Use `|` block scalars for prose.
- `depends_on` must reference existing issue IDs. No cycles.
- Split per platform when Android and macOS work are independent; use `[cross]` only for
  work that must land together (e.g. end-to-end tests).
- `tdd` entries are concrete, falsifiable test names that fail before the implementation
  exists: `"<layer>: <unit>_<condition>_<expectedResult>"` — exactly three lowerCamelCase
  segments, no spaces, no parentheses, quoted in YAML. The sync script wraps each entry in
  backticks. `validate` enforces the format. Not tests: restated acceptance
  (`featureWorks_correctly_passes`), review steps (`reviewChecklistComplete`), prose.
- Layer prefix picks the harness (see `docs/planning/README.md` → Test layers):

  | Prefix | Harness | Runs |
  |---|---|---|
  | `unit:` | JUnit5 (+Turbine, Robolectric where framework types are unavoidable) / Swift Testing; fakes from `core/testing` / `TandemTestSupport` | every PR |
  | `conformance:` | `tools/conformance` against `protocol/vectors/` on both codecs | every PR |
  | `integration:` | JVM client ↔ real Mac server (E15-15) or in-process loopback (two real sessions over E00-19 / E00-25 pairs, real TLS on localhost) | every PR (macOS runner) |
  | `instrumented:` | Android emulator via Gradle Managed Devices (E00-21) | PRs touching `android/**`, nightly |
  | `ui:` | Compose UI test under Robolectric (E00-20) / XCUITest (E00-26) | every PR |
  | `manual:` | Physical device gate per `docs/testing/manual-gates.md` (E00-23) — e.g. overnight Doze, 4 GB transfer, real messaging-app reply | phase exit |
  | `security:` | `tools/mitm-lab`, `tools/pcap-audit`, `nmap`, `tools/log-audit` (E15) | core/* PRs (subset), phase exit (full) |
  | `ci:` | Repo/tooling checks: lint-rule fixtures, `buf lint`/`breaking`, vector schema validation, manifest/link checks, workflow path filters | every PR |

- `spike`/`adr` use `tdd: []` and put the deliverable in `acceptance`. `doc` uses `tdd: []`
  or only `ci:` entries (e.g. link check, vector schema validation).
  `story`/`task`/`test` must list at least one entry.
- Seams: an issue whose tests need a fake names it in `description` (e.g. "takes a `Clock`
  (E00-18)") and lists the seam issue in `depends_on`.
