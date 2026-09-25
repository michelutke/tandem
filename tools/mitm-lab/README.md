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
