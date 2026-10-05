tools/pcap-audit — E15-04: tshark-based capture harness asserting TLS-1.3-only and no canary strings on the wire.

E15-04 provides the capture and parsing primitives only: `capture.sh` (filtered capture) and
`analyze.py` (structured record list + classification). The "only TLS 1.3 records" assertion
(E15-05, `tls13_assertion.py`) and the canary-string scan (E15-06, `canary_scan.py`) are separate
tools built on top of `analyze.py`'s record list.

`tshark` is required to run any of this (`which tshark` to check); all tests here shell out to a
real `tshark` against committed fixture pcaps rather than pre-baked JSON, since a working `tshark`
was available in the environment this was implemented in.

## capture.sh

Starts a `tshark` capture filtered to `tcp port <port>` on a given interface (default `lo0`), for
either a fixed duration or the lifetime of a scripted session.

```sh
# Fixed duration
tools/pcap-audit/capture.sh --port 7623 --out session.pcapng --duration 10

# Scripted session — capture.sh exits with the script's exit status
tools/pcap-audit/capture.sh --port 7623 --out session.pcapng --script -- ./run-pairing-session.sh
```

The BPF capture filter (`tcp port <port>`) means frames on any other port are never written to
the output file — there is no post-hoc filtering step.

Capturing on `lo0` needs read access to `/dev/bpf*`. On a fresh macOS install without
Wireshark's ChmodBPF helper (or without the current user in the `access_bpf` group), `tshark -i
lo0` fails with a permission error; install Wireshark (which ships ChmodBPF) or grant BPF access
another way. `tools/pcap-audit/tests/test_capture.py` probes for this and skips its live-capture
test if capture isn't permitted, rather than failing the suite.

## analyze.py

Parses a pcap into a structured record list (frame number, TCP stream, protocol, TLS record
content types, negotiated TLS version when a ServerHello is present, TCP payload length) and can
classify a single session.

```sh
python3 tools/pcap-audit/analyze.py session.pcapng --port 7623            # full record list (JSON)
python3 tools/pcap-audit/analyze.py session.pcapng --port 7623 --classify # one classification object
```

`--classify` prints one of:

- `{"classification": "tls1.3", "negotiatedVersion": "0x0304"}`
- `{"classification": "tls1.2", "negotiatedVersion": null}`
- `{"classification": "plaintext", "frame": <n>, "payloadOffset": <byte offset in the frame>}`
- `{"classification": "unknown"}` — TLS traffic seen but no ServerHello observed (e.g. a partial capture)
- `{"classification": "empty"}` — no matching frames

TLS 1.3 is identified only by a ServerHello's `supported_versions` extension equal to `0x0304`;
the record-layer legacy version is `0x0303` in TLS 1.3 too and is never used for detection.

## tls13_assertion.py (E15-05)

Fails if any record on the (optionally port-filtered) record list is not part of a TLS 1.3
session: a ServerHello whose negotiated version isn't `0x0304` (TLS 1.2 or older), or a
payload-bearing frame `tshark` didn't dissect as TLS at all (plaintext).

```sh
python3 tools/pcap-audit/tls13_assertion.py session.pcapng --port 7623
```

Prints one of:

- `{"result": "pass", "recordCount": <n>}`
- `{"result": "fail", "reason": "plaintext", "frame": <n>, "payloadOffset": <n>}`
- `{"result": "fail", "reason": "tls1.2", "frame": <n>, "negotiatedVersion": "0x0303"}`

Exits 0 on pass, 1 on fail.

The real-app scenario (`pcapAudit_jvmHarnessPairAndReconnect_zeroNonTls13Records`, a capture of
the E15-15 JVM harness pairing + restart-reconnect session against the real Mac server) is
skipped in `tests/test_tls13_assertion.py`: E15-15 (and the E15-21 JVM client it joins) aren't
implemented in this repo yet — only the E15-22 Mac driver (`tools/harness/mac-driver.sh`) exists
so far. The test checks for `tools/harness/jvm-harness.sh` and runs for real once that lands.

## canary_scan.py (E15-06)

Scans a supplied ASCII canary string (e.g. `TANDEM-CANARY-<random>`) over (a) the raw bytes of
every frame in the capture — any port, headers included — and (b) every reassembled TCP stream,
so a canary split across two segments is still found. There's no port filter: this tool always
scans the whole capture, matching the whole-interface capture filter used for canary runs.

```sh
python3 tools/pcap-audit/canary_scan.py session.pcapng --canary "TANDEM-CANARY-<random>"
```

Prints one of:

- `{"result": "pass", "occurrences": 0}`
- `{"result": "fail", "occurrences": <n>, "frameHits": [...], "streamHits": [{"stream": <n>, "frames": [...]}]}`

Exits 0 on pass (0 occurrences), 1 on fail.

## canary.sh (E15-07)

Automates the PRD test-strategy canary procedure: generates a fresh `TANDEM-CANARY-<random>`
(128 random bits — two runs never reuse one) and runs the enabled injection steps.

```sh
tools/pcap-audit/canary.sh --dry-run                 # print planned steps + exact commands, no device touched
tools/pcap-audit/canary.sh --dry-run --phase1-only    # plan only the automated display-name step (CI mode)
tools/pcap-audit/canary.sh --phase1-only              # actually run the automated Phase 1 pairing + capture + scan
tools/pcap-audit/canary.sh                            # run every enabled step against an attached adb device
```

Steps:

1. **phase1 (display-name)** — always enabled, runs everywhere. Feeds the canary through the real
   E15-15 JVM harness client's production `DeviceInfoProvider` as `--display-name`, pairs it with
   the real Mac app, restart-reconnects, all inside one whole-interface tshark capture that
   `canary_scan.py` then scans (`tools/harness/integration/e15-07-canary-phase1.sh`). No test-only
   wire payload or debug channel exists for this — the canary only ever rides
   `PairRequest.deviceInfo.displayName` during a genuine pairing.
2. **notification (E30)** — `adb shell am broadcast -a dev.tandem.companion.POST --es kind canary
   --es nonce <nonce>` through the companion app (E00-22).
3. **clipboard (E31-06)** — `adb shell am start -a android.intent.action.SEND` with the canary as
   `text/plain`, targeting the share-target activity.
4. **file (E40-11)** — not built yet (Phase 4 file transfer); disabled until that issue lands.

Steps 2-4 need a live phone with adb attached; they are not runnable in CI. Each is gated by a flag
naming its owning feature issue (`--disable-e30`, `--disable-e31-06`, `--enable-e40-11`) — once
that issue is done, `--disable-<issue>` exits non-zero rather than silently skipping the step, and
`--enable-e40-11` exits non-zero until E40-11 actually lands. `--phase1-only` is the separate,
always-legal mode for an automated/CI run with no Android device at all.

The live-phone capture/scan for steps 2-4 is done by wrapping a real (non-`--dry-run`) invocation
of this script in `capture.sh`, per the manual gate procedure in `docs/testing/manual-gates.md`.

## check-proto-schema.sh (E15-07 CI check)

```sh
tools/pcap-audit/check-proto-schema.sh   # scans protocol/proto/** by default
```

Fails (exit 1, offending lines on stdout) if any `message` declaration under `protocol/proto/**`
has a name containing `Debug`, `Echo`, or `Test` — there is no test-only wire message for canary
injection or anything else. Exits 0 otherwise.

## flows.py (E60-06)

Flow audit for the control + media connection pair. The media connection terminates on the same
single Tandem port as the control connection (no second listener), so a mirror-session capture holds
two distinct TCP flows on that port. Fails if any TCP flow in the capture targets another port, is
not TLS 1.3, or if fewer than `--min-flows` (default 2) flows are seen, so a pass is never vacuous.

```sh
python3 tools/pcap-audit/flows.py session.pcapng --port 7623 [--min-flows 2]
```

Prints `{"result": "pass", "flowCount": <n>, "flows": [...]}` or `{"result": "fail", "reason":
"off-port-flow" | "non-tls13-flow" | "too-few-flows", ...}`; exits 0 on pass, 1 on fail.

`tools/harness/integration/e60-06.sh` runs it (with `tls13_assertion.py` and an `lsof` single-listener
check) against the real Mac server with a JVM harness control + held media connection; it runs in the
jvm-harness workflow. The matching security tests in `tests/test_flows.py` are opt-in locally via
`TANDEM_E60_06_LIVE=1`.

## Fixtures

`fixtures/` holds small pcaps generated once from real local traffic:

- `tls13-handshake.pcapng` — `openssl s_server`/`s_client -tls1_3` handshake + a few app-data records.
- `tls12-handshake.pcapng` — the same via `-tls1_2`.
- `plaintext-payload.pcapng` — a single unencrypted TCP payload (`nc`).
- `canary-single-payload.pcapng` — a single unencrypted TCP payload (`nc`) carrying the fixture
  canary string whole, in one frame.
- `canary-non-tandem-port.pcapng` — the same, on a different port, to prove `canary_scan.py`
  doesn't filter by port.
- `canary-split-segments.pcapng` — a Python socket driver sends the fixture canary string as two
  separate `send()` calls (`TCP_NODELAY`, a short sleep between them) so it lands in two TCP
  segments; the canary is only recoverable via stream reassembly.

The canary fixtures all embed the same fixed, non-secret string
(`TANDEM-CANARY-0123456789abcdef0123456789abcdef`) — structural test data, not a real
pairing/session canary (those are generated fresh per run by E15-07).

- `two-tls13-flows-one-port.pcapng` — `tls13-handshake.pcapng` duplicated with the second copy's
  client port rewritten (`make_two_flow_fixture.py`, needs `editcap`/`mergecap`): two TLS 1.3 flows on
  one server port.

Regenerate all of the above with `tools/pcap-audit/fixtures/regenerate.sh` (same
tshark/openssl/nc/python3-on-lo0 requirements as above). The keys used for the TLS fixtures are
throwaway and not committed.

## Setup

```sh
cd tools/pcap-audit
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Running

```sh
cd tools/pcap-audit
pytest tests -q
```
