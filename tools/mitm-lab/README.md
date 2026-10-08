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

## E73-05: manual pairing brute-force and downgrade scenarios

`tools/mitm-lab/e73-05-manual-pairing/` -- five scenarios against the real Mac app launched with the
DEBUG-only `-HarnessOpenManualPairingWindow YES` hook (a manual-mode window: no QR, no secret, the
same 120 s / 3-attempt window as QR, ADR-008), driven through the JVM harness client's
`RAWOPENUNPINNED` (an unpinned dial, since manual pairing has no QR fingerprint) and `RAWMANUAL
COMMIT` / `RAWMANUAL REVEAL [NONCE=<hex>|PREFIX]` commands (a real `Commitment`, or a `Reveal` the real
state machine would never send). Each scenario launches its own Mac process (the window is single-use).

- `mitmLab_manualPairingBruteForce_fourthAttempt_rejected` -- three attempts that finish the commit
  phase and then reveal a wrong nonce burn the window; the 4th connection is rejected in the handshake.
- `mitmLab_manualPairing_commitPhaseSkipped_rejectedNoPin` -- `Reveal` without a prior `Commitment`
  is rejected, no pin.
- `mitmLab_manualPairing_fingerprintPrefixOnly_rejectedNoPin` -- a fingerprint prefix offered in
  place of the committed nonce is rejected, no pin.
- `mitmLab_manualPairing_messageInQrPairingSession_connectionClosed` -- a `Commitment` injected into a
  QR window (opened with the E15-09 `-HarnessOpenPairingWindow YES` hook) closes the connection.

- `mitmLab_manualPairing_pairRequestOnManualWindow_rejectedAttemptBurned` -- the reverse downgrade: three
  QR `PairRequest`s on a manual window each burn one attempt, the 4th connection is rejected.

```sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e73-05-manual-pairing/scenarios --timeout 300
ruby tools/mitm-lab/test/e73_05_scenarios_test.rb
```

## E60-05: media ticket binding scenarios

`tools/mitm-lab/e60-05-media-ticket/` -- six scenarios against the real Mac app launched with the
DEBUG-only `-HarnessMediaTickets YES` hook (the real ticket table, issuer, registry and media
acceptor, no mirror window), driven through the JVM harness client's `RAWOPEN`, `RAWTICKET`
(real `RequestMediaTicket`/`MediaTicketGrant`) and `MEDIAOPEN` (a second pinned mTLS connection
carrying a chosen `MediaHello`) commands; scenario 5 uses a second paired JVM client for peer B's
certificate. Every scenario completes mTLS first (`OK MEDIA_CONNECTED`), so a rejection is the ticket
layer, not the handshake. The Mac prints `harness-media-event: ticketRejected(<reason>)` (reason only,
never ticket bytes) and `harness-media-event: bound`; a pass needs the Mac to close the connection,
the expected reason, and no `bound` for the rejected connection. The acceptor's local reasons collapse
the SPEC ones: consumed -> `reused`, revoked and peerMismatch -> `otherSession`.

- `..._mediaHelloWithoutTicket_...` -> `missing`; `..._mediaReusedTicket_...` -> `reused` (first use is bound);
  `..._mediaTicketAfter31s_...` -> `expired`; `..._mediaTicketFromEndedSession_...` and
  `..._mediaTicketOnOtherPeersClientCert_...` -> `otherSession`.
- `..._mediaConnectionNoHelloFor6s_closedProtocolTimeout` -- the silent connection is closed by the
  Mac's 5 s first-frame deadline (observed 4-6.5 s after the handshake); that path emits no acceptor event.

```sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e60-05-media-ticket/scenarios --timeout 300
```

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

Every scenario completed in well under a minute in practice.

## E15-16: menu-bar version-mismatch check

`mitmLab_helloUnsupportedMajorVersion_menuShowsVersionError` (the UI half of E15-11's version-mismatch
scenario) is deliberately not a mitm-lab script: reading the status item through the accessibility tree
needs OS Accessibility permission, which CI and dev machines don't grant to scripts. It is covered by
CI-runnable tests instead:

- `macos/Packages/TandemTransport/Tests/TandemTransportTests/VersionMismatchHookLoopbackTests.swift` --
  real mTLS listener, trusted peer sends `VersionHello` major 99: not registered, but
  `onSessionRegistered` sees the session ending in `.failed(.versionMismatch)`.
- `macos/TandemAppTests/VersionMismatchMenuTests.swift` -- real `ByteStreamSession`/`VersionHandshake`
  over an in-memory stream, through `ConnectionStateRelay`: `MenuBarViewModel` and
  `ErrorBannerViewModel` both show the version-mismatch error.
- `macos/TandemUITests/ScenarioVersionMismatchMenuUITests.swift` -- XCUITest of the seeded
  `versionMismatchMenu` scenario window (menu label and banner text).

## E15-10: certificate-abuse scenarios

`tools/mitm-lab/e15-10-cert-abuse/` — six TLS-handshake-level attacks (as opposed to E15-09's
pairing-*protocol*-level ones) against the real Mac app and the real JVM client (`lib/e15-10-
common.sh`, same self-contained-per-scenario convention as E15-09): an unknown client cert outside
a pairing window, an impostor server whose cert fingerprint doesn't match what the client pinned,
certificates swapped between two paired devices, a phone reconnecting after its trust record was
deleted on the Mac while it was offline (AC-09), a client presenting a paired phone's genuine cert
signed with a foreign key, and an impostor server presenting the Mac's own genuine cert without its
private key.

No new raw `HarnessCli.kt` commands were needed — every scenario is a TLS-handshake attack, so the
existing `RAWOPEN` (E15-09) is enough to dial and observe rejection. Trust is bound to SPKI
fingerprints only (invariant 3): `-HarnessSeedTrust` accepts any fingerprint regardless of how its
cert was generated, so the "paired device" certs these scenarios swap or borrow keys from are the
same ephemeral `openssl`-generated P-256 certs the E15-08 self-tests already use
(`selftest/lib/gen-cert.sh`/`spki-fingerprint.sh`, reused as-is).

The cert/key-mismatch scenarios (3, 5, 6) cannot be built with `openssl s_client`/`s_server`, Ruby's
`OpenSSL::SSL::SSLContext`, Python's `ssl` module, or even a hand-rolled OpenSSL C program — every
one of them calls the equivalent of `ossl_x509_check_private_key()` internally whenever a
certificate and a key end up attached to the same `CERT_PKEY` slot, and *silently drops the
mismatched key* on failure instead of erroring (verified empirically against OpenSSL 3.6.4: loading
the key before the certificate does **not** avoid this, contrary to an earlier assumption here — the
check runs regardless of load order, so that approach would have silently tested "no client
certificate at all" in every mismatch scenario, never a real signature mismatch). Go's `crypto/tls`
performs the equivalent check only inside its `tls.X509KeyPair()` convenience constructor; a
`tls.Certificate{}` struct literal built directly, with an unrelated `PrivateKey`, is never passed
through it. `lib/mismatched_cert_client.go`/`mismatched_cert_server.go` (built on demand via `go
build`) do exactly that, then perform a real TLS 1.3 handshake and a post-handshake read (TLS 1.3:
the client's own `Handshake()` succeeds the instant it has *sent* its
Certificate/CertificateVerify/Finished, before the peer has verified any of it — only a subsequent
read surfaces the peer's rejection alert).

Run the suite:

```sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e15-10-cert-abuse/scenarios --timeout 300
```

All six scenarios pass in well under a minute each (no pairing-window expiry wait, unlike E15-09).

## E21-06: discovery-hint scenario

`tools/mitm-lab/e21-06-discovery-hint/scenarios/spoofedAdvertisement_validIdWrongKey_pinCheckFailsNoAppData`
— an impostor at a discovery-resolved candidate address with a different key fails the real JVM
client's pin check and receives zero application bytes. Reuses the E15-10 library; run with
`ruby tools/mitm-lab/runner.rb tools/mitm-lab/e21-06-discovery-hint/scenarios --timeout 120`.

## E20-20: authenticated CONTROL-flood scenarios

`tools/mitm-lab/e20-20-auth-flood/` — an already-paired, authenticated phone (JVM harness client,
identity seeded via `-HarnessSeedTrust`, reusing `e15-10-common.sh`) floods the real Mac's CONTROL
channel with the harness `FLOOD HEARTBEAT|CONTROL <perSecond> <seconds>` command. Both scenarios
expect the Mac to close the session with `LIMIT_EXCEEDED` and leave its trust store unchanged:
non-Heartbeat CONTROL past 60/s (D-61), and 1000 Heartbeats/s (D-66 counts Heartbeats the Mac
receives toward the same cap). Needs the real Mac app, so they run only on macOS and are not part
of `audit-step.sh`; `test/e20_20_scenarios_test.rb` checks their structure. The phone-side D-60
reply cap (at most one reply/s) is covered by `HeartbeatResponderTest`; a Mac test double that
floods a phone does not exist yet.

## E15-20: pre-auth DoS and timeout scenarios

`tools/mitm-lab/e15-20-preauth-dos/` -- five scenarios against the real Mac app (SPEC.md §10, E01-22):
stalled TCP (closed <= 11 s), TLS done without `VersionHello` (closed <= 6 s after TLS, observed as a
close -- no pre-auth close code exists on the wire), a 20-connection single-source flood (<= 2 open per
source, paired peer from another source Ready <= 5 s), a 10-failed-handshake burst (source refused 60 s,
other source Ready), and three idle pairing candidates exhausting the window (later correct
`PairRequest` gets no `PairAccepted`).

Distinct sources are loopback aliases 127.0.0.2..127.0.0.4. macOS only configures 127.0.0.1, so each
scenario adds missing aliases with `sudo -n ifconfig lo0 alias` (removed at teardown) and exits 1 with
the exact command to run if passwordless sudo is unavailable. `lib/preauth_probe.go` (built via `go
build`) supplies source-bound sockets.

```sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e15-20-preauth-dos/scenarios --timeout 300
ruby tools/mitm-lab/test/e15_20_scenarios_test.rb   # structure checks only
```

## E70-09: key-rotation abuse scenarios

`tools/mitm-lab/e70-09-rotation/` -- six scenarios against the real Mac app (SPEC.md #key-rotation),
each asserting the connection was closed or answered with `RotationReject` for the expected reason and
that the Mac's trust store (record count and fingerprints via `-HarnessListTrust`) is identical before
and after: `KeyRotation` sent before `VersionHello` (Mac ignores it and closes at the 5 s hello
deadline), in a pairing-window session (wrong payload, `PAIRING_FAILED` close, no reject), from an
unpinned peer (handshake rejected, no session to send on), a `KeyRotation` built over session A's
`RotationChallenge` and delivered on session B (`INVALID_SIGNATURE`), and one whose `newSpki` is
another paired peer's key (`DUPLICATE_KEY`; the harness holds that key so both signatures verify).

Three JVM harness client commands (`RawRotation.kt`, real `RotationProof` transcript, real identity
key) build the frames: `RAWKEYGEN` (hold a new key, print its fingerprint to seed as a second paired
peer), `RAWCHALLENGE` (print the session's `RotationChallenge`), `RAWROTATE [CB=<hex>] [HELDKEY]`.
`lib/rotation_before_hello_client.go` sends the pre-`VersionHello` frame, which no real client can.

The sixth scenario, `mitmLabRotation_pendingMacKeyOfferedBeforeAllAcks_unackedPhoneKeepsOldPinOnly`, starts the
Mac's own rotation: the DEBUG-only `-HarnessMacRotation YES` hook (`HarnessHooks+MediaTickets.swift`) composes the
production `MacKeyRotation` (E70-16) over the harness keychain and trust store and begins a rotation at launch,
printing `harness-mac-rotation: <outcome>` (and `harness-mac-rotation-switched` if every phone acked; never key
material). The JVM client command `RAWMACROTATION [ACK|NOACK]` (`RawMacRotation.kt`) sends the phone's
`RotationChallenge`, receives the Mac's `KeyRotation`, verifies both signatures with the real `RotationProof` and
prints `EVENT MAC_ROTATION_OFFERED <newSpkiFingerprintHex> VERIFIED`; the scenario never acks. It then shows the
unacked phone keeps the old pin only: a connection pinned to the old key still succeeds (the Mac's listener
identity is unchanged), one pinned to the pending key alone is rejected, and the Mac logs no switch.

```sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e70-09-rotation/scenarios --timeout 300
ruby tools/mitm-lab/test/e70_09_scenarios_test.rb   # structure checks only
```

## E62-08: input-authorization scenarios

Invariant 8 (remote input only during a user-started mirror session), proven against input the real
Mac app sends but its mirror window never would. The DEBUG-only Mac stdin command (`-HarnessInteractiveCommands YES`)
`SENDINPUT <phoneFpHex> <TAP|TAPOUT|SETTEXT> <count> <perSecond> <NONE|RANDOM|sessionIdHex> [text]` sends the
crafted `InputEvent`s; `MIRRORREQUEST <fpHex>` and `MIRRORSTOP` start and end a real mirror session (with
`-HarnessMediaTickets YES`, which also prints `harness-mirror-session: <hex>`, the phone-minted reference).

- Integration variant: `tools/harness/integration/e62-08.sh` (macOS, no phone). The JVM harness client's
  `INPUTWATCH`/`INPUTSTATS` run the real `InputGate` with a recording dispatcher (`RemoteInputHarness.kt`) and
  no mirror consent; the real Mac sends a Tap, then a `SetText` carrying a canary. Expects zero dispatcher
  calls and one drop record per event, and `tools/log-audit/log-audit.sh` over the client capture and the Mac
  log finds zero canary occurrences (`inputGate_realMacSendsInputWithoutSession_zeroDispatchOneDropRecord`,
  `logAudit_droppedSetTextCanary_absentFromLogs`).
- Device scenarios: `tools/mitm-lab/e62-08-input-auth/scenarios/` (six, `lib/e62-08-device.sh`) target the real
  phone app over adb with `tools/companion-app`'s `InputCounterActivity` in the foreground (one logcat line per
  touch that reaches it). No session, a stale session reference, input after the session stopped, a 1000/s flood
  (at most 240 touches in any wall-clock second) and out-of-range coordinates (dropped, not clamped) each assert
  zero or bounded touches at the counter and the phone's `InputGate` drop log. Needs a debug build with the
  remote-input accessibility service enabled; the operator scans the pairing QR the script prints, and the
  script presses the on-phone prompt through uiautomator (`E62_08_MIRROR_TAPS` overrides the button labels).
  Not run in CI or by `audit-step.sh`.

```sh
tools/harness/integration/e62-08.sh
ruby tools/mitm-lab/runner.rb tools/mitm-lab/e62-08-input-auth/scenarios --timeout 600   # phone on adb
ruby tools/mitm-lab/test/e62_08_scenarios_test.rb   # structure checks only
```
