tools/pcap-audit — E15-04: tshark-based capture harness asserting TLS-1.3-only and no canary strings on the wire.

This issue (E15-04) provides the capture and parsing primitives only: `capture.sh` (filtered
capture) and `analyze.py` (structured record list + classification). The "only TLS 1.3 records"
assertion (E15-05) and the canary-string scan (E15-06) are separate tools built on top of
`analyze.py`'s record list.

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

## Fixtures

`fixtures/` holds three small (~16 KB total) pcaps generated once from real local traffic:

- `tls13-handshake.pcapng` — `openssl s_server`/`s_client -tls1_3` handshake + a few app-data records.
- `tls12-handshake.pcapng` — the same via `-tls1_2`.
- `plaintext-payload.pcapng` — a single unencrypted TCP payload (`nc`).

Regenerate them with `tools/pcap-audit/fixtures/regenerate.sh` (same tshark/openssl/nc-on-lo0
requirements as above). The keys used to produce them are throwaway and not committed.

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
