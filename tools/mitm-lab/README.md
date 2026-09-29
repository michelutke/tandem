tools/mitm-lab — E15-08: scenario harness scaffolding + scripted-scenario runner (scripted MITM
scenarios: wrong/swapped certs, pairing replay, downgrade, pre-auth DoS).

This issue builds the scaffold only: a scenario file format and a runner that executes a
directory of scenarios and reports pass/fail. The concrete production scenarios (pairing abuse
E15-09, certificate abuse E15-10, downgrade/resumption/0-RTT E15-11, pre-auth DoS E15-20, plus
media-ticket E60-05, input E62-08, rotation E70-09) are separate issues built on this scaffold,
each adding its own scenario directory once the real Mac server / Android client (E15-15) exist.

## Scenario format

A scenario is one executable file living directly under a scenario directory (not recursive). Its
leading `#`-comment header declares metadata as `# mitm-scenario-<key>: <value>` lines:

```
#!/usr/bin/env bash
# mitm-scenario-name: my_scenario        (optional; defaults to the file's basename)
# mitm-scenario-role: client|server      (required: which side this scenario plays)
# mitm-scenario-expect: handshakeRejected | noPairAccepted | closedWithCode(<CODE>)  (required)
# mitm-scenario-timeout: 15              (optional seconds; default 30)
...script body...
echo "OUTCOME: handshakeRejected"
```

The scenario can be written in any language (bash + `openssl`, Ruby, etc.) as long as it is
executable (`chmod +x`) and prints exactly one `OUTCOME: <value>` line to stdout before exiting —
the runner reads the *last* such line as the observed outcome. A scenario passes only when the
observed outcome equals its declared `mitm-scenario-expect`; anything else — a different outcome,
a non-zero exit with no `OUTCOME:` line, a crash, or exceeding its timeout — is a failure, never a
silent pass.

When invoked with `--target-host`/`--target-port`, the runner passes them to every scenario as the
`MITM_TARGET_HOST`/`MITM_TARGET_PORT` environment variables (the peer under test — the real Mac
listener or Android client, once E15-15 exists). A scenario that stands up its own throwaway peer
(e.g. an impostor server) is free to ignore these and manage its own target.

## Runner

```sh
ruby tools/mitm-lab/runner.rb SCENARIO_DIR [--target-host HOST] [--target-port PORT] [--timeout SECONDS]
```

Executes every scenario file under `SCENARIO_DIR`, prints one line per scenario (PASS/FAIL, role,
expected vs. observed outcome, duration), and exits non-zero naming every failing scenario if any
scenario failed to match its declared expectation, timed out, or the directory contained no
scenario files at all (an empty or all-non-executable directory is always a failure).

## Self-tests

- `ruby tools/mitm-lab/test/runner_test.rb` — unit tests of the runner itself (discovery, outcome
  matching, timeout handling, empty-directory handling) against fixture scenarios under
  `test/fixtures/scenarios/`, including one that talks to a local stub TCP peer.
- `tools/mitm-lab/selftest/run.sh` — an end-to-end self-test proving the scenario format works
  against real TLS, using `openssl s_server`/`s_client` as a stand-in for the not-yet-built real
  Mac listener and Android client: a client-role scenario (`tls12_client_rejected_by_tls13_only_server.sh`)
  and a server-role scenario using a tiny pinning client
  (`wrong_server_cert_fails_pin_check.sh`, `selftest/lib/pinning-client.sh`). Uses only ephemeral,
  temp-file certs/keys — no keychain, no signing.

## E15-09: pairing-abuse scenarios

`tools/mitm-lab/e15-09-pairing-abuse/` — the first scenario directory built on this scaffold against
the *real* Mac app (E15-15's `tools/harness/mac-driver.sh`) and a *real* JVM pairing client, not a
throwaway stand-in. Each scenario is self-contained exactly like the self-tests above (it ignores
`MITM_TARGET_HOST`/`MITM_TARGET_PORT`): a single-use pairing window can only ever be opened once per
Mac-process launch, so every scenario needing its own fresh window builds and launches its own Mac
process (`lib/e15-09-common.sh`, sourced by every scenario file).

Rather than driving the real `PairingStateMachine` (which can only ever send a *correct*
`PairRequest`), these scenarios drive five low-level commands E15-09 added to the JVM harness client
CLI (`android/harness/jvm-client/.../HarnessCli.kt`: `RAWOPEN`, `RAWSEND`, `RAWSENDPROOF`,
`RAWREVOKE`, `RAWCLOSE`) that construct a pairing-candidate connection's frames directly — reusing
the real `core/crypto` `PairingProof` HMAC implementation (never a reimplemented copy) so a scenario
can supply a wrong, replayed, or malformed proof, or send `Revoke` before `PairAccepted`, while
every *correct* value it does use is still the real formula.

Run the suite:

```sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e15-09-pairing-abuse/scenarios --timeout 300
```

Each scenario manages its own timeout via its `mitm-scenario-timeout` header (up to 300s — one
scenario waits a real 121 wall-clock seconds for the pairing window's 120s expiry, per SPEC.md
#pairing "Pairing window"); `--timeout` above only sets the runner's fallback default. Building the
real Mac app and resolving the JVM classpath once per scenario (there is no shared build cache
across scenario processes, matching the existing per-script convention in
`tools/harness/integration/e14-16.sh`/`e14-20.sh`/`e15-15.sh`) makes a full run slow (tens of
minutes) — this is deliberately not yet wired into CI as a required check, matching E15-08's own
`tools/conformance/run.sh` precedent above.

## E15-11: downgrade / resumption / 0-RTT / protocol-version scenarios

`tools/mitm-lab/e15-11-version-scenarios/` — seven scenarios (four base scenarios, one of which
splits into two files, plus two Cycle 4 additions) against the real Mac app and, for one of them,
the real JVM (Android `core`) client. Six are TLS-handshake/version-negotiation attacks, driven the
same self-contained-per-scenario way as E15-09/E15-10 (`lib/e15-11-common.sh`, no pairing window);
the seventh (`mitmLab_androidClientAfterTicketIssued_nextHelloOffersNoPsk`) needs no real Mac app at
all — a scripted Go server plays the "real Mac" role instead, to prove the real *client's* own
resumption behavior.

- `mitmLab_tls12OnlyClientHello_protocolVersionAlert` — a TLS 1.2-only ClientHello against the real
  Mac's TLS-1.3-only listener fails with a `protocol_version` alert.
- `mitmLab_fullHandshake_zeroSessionTicketsIssued` / `mitmLab_resumptionAttempt_neverResumed` — a
  real full mTLS handshake issues 0 `NewSessionTicket` messages (`NWListenerFactory` disables both
  TLS tickets and resumption), and a saved-session or forged-PSK resumption attempt always falls
  back to a full handshake (or is rejected) — TLS 1.3 resumption being entirely ticket-based means
  there is, empirically, no session file to even attempt `-sess_in` resumption with.
- `mitmLab_zeroRttEarlyData_zeroEarlyBytesDelivered` — 0-RTT early data is structurally impossible
  against a listener that never issues a ticket (same finding as the sibling scenario above),
  verified against a real 0-RTT-capable throwaway server as this script's own positive control.
- `mitmLab_helloUnsupportedMajorVersion_closedWithVersionMismatch` — a peer completing real mTLS
  then sending a hand-built `VersionHello` with an unsupported major version gets closed within a
  few milliseconds, versus staying open for the real client's own `major=1` on an otherwise
  identical connection (`VERSION_MISMATCH` carries no wire signal at all per `docs/protocol/
  SPEC.md #errors-and-close-codes`, so this scenario substitutes a by-construction timing
  discriminator rather than inferring the close code after the fact).
- `mitmLab_clientWithoutTandemAlpn_handshakeFails` (Cycle 4) — a wrong or missing ALPN fails the
  handshake; empirically, the real Mac's TLS stack (Apple's `Network`/`Security` framework) sends a
  fatal `internal_error` alert for a wrong ALPN, not the RFC 7301 `no_application_protocol` alert
  the backlog text assumed — see that scenario file's own header for the reproduced discrepancy.
- `mitmLab_androidClientAfterTicketIssued_nextHelloOffersNoPsk` (Cycle 4) — a scripted TLS 1.3
  server (`lib/ticket_probe_server.go`, tickets left enabled) issues a real `NewSessionTicket` to
  the real JVM harness client, then inspects that client's very next `ClientHello`'s raw extensions
  for `pre_shared_key`/`early_data` — neither ever appears, confirming empirically that
  `SslClientFactory`'s "fresh `SSLContext` per connection" design actually prevents resumption.

Two scenarios need TLS/wire-level control no scripting-language binding offers: a hand-built
app-layer `Envelope{VersionHello}` frame, and a server that issues real tickets and then parses a
raw ClientHello's extensions. `lib/version_hello_client.go`/`lib/ticket_probe_server.go` (built on
demand via `go build`) do exactly that, using the same real `crypto/tls` (never a reimplemented TLS
stack) technique E15-10 established.

Run the suite:

```sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e15-11-version-scenarios/scenarios --timeout 300
```

Every scenario completed in well under a minute in practice. `mitmLab_helloUnsupportedMajorVersion_
menuShowsVersionError` (the UI half of the version-mismatch scenario, reading the real Mac menu-bar
status item's text via the accessibility tree after the same attack) is not included here: the
Mac app's `MenuContentView` does not yet wire any real per-connection state into
`MenuBarViewModel`/`ErrorBannerViewModel` at all (both are constructed with `stateStream: nil`,
`macos/TandemApp/TandemApp.swift`) — a real attack against the harness-launched app today has
nothing to surface in that UI regardless of what closed it. See this issue's PR description for
that gap; it blocks only this one UI-observability check, not the six scenarios above.
