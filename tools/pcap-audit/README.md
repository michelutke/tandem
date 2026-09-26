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
