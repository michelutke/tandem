#!/usr/bin/env python3
"""tools/pcap-audit/analyze.py — parses a pcap captured by capture.sh into a structured record
list, and classifies a single Tandem-port session as TLS 1.3, TLS 1.2 or a plaintext TCP payload
(E15-04).

TLS 1.3 is identified only by a ServerHello's `supported_versions` extension equal to 0x0304; the
record-layer legacy version is 0x0303 in TLS 1.3 too and MUST NOT be used to detect it.

Usage:
    python3 analyze.py <pcap> [--port <port>]              # print the structured record list (JSON)
    python3 analyze.py <pcap> [--port <port>] --classify    # print one classification object (JSON)

E15-05 (the "only TLS 1.3 records" assertion) and E15-06 (the canary scan) consume the record
list this module produces; this module does not implement either assertion itself.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

TSHARK = os.environ.get("TSHARK_BIN", "tshark")

TLS13_SUPPORTED_VERSION = "0x0304"
SERVER_HELLO_TYPE = 2

FIELDS = [
    "frame.number",
    "tcp.stream",
    "frame.protocols",
    "tls.record.content_type",
    "tls.record.opaque_type",
    "tls.handshake.type",
    "tls.handshake.extensions.supported_version",
    "tcp.len",
]


def _run_tshark(args: list[str]) -> str:
    result = subprocess.run([TSHARK, *args], capture_output=True, text=True, check=True)
    return result.stdout


def _int_list(raw: str) -> list[int]:
    return [int(v, 0) for v in raw.split(",") if v]


def _hex_list(raw: str) -> list[str]:
    return [v for v in raw.split(",") if v]


@dataclass
class Record:
    frame: int
    stream: int | None
    protocol: str
    tls_content_types: list[int]
    tls_handshake_types: list[int]
    tls_negotiated_version: str | None
    payload_len: int

    def as_dict(self) -> dict[str, Any]:
        return {
            "frame": self.frame,
            "stream": self.stream,
            "protocol": self.protocol,
            "tlsContentTypes": self.tls_content_types,
            "tlsHandshakeTypes": self.tls_handshake_types,
            "tlsNegotiatedVersion": self.tls_negotiated_version,
            "payloadLen": self.payload_len,
        }


def parse_records(pcap: Path, port: int | None = None) -> list[Record]:
    """Parses `pcap` into one Record per frame, in capture order."""
    args = ["-r", str(pcap), "-T", "fields", "-E", "separator=|", "-E", "occurrence=a"]
    if port is not None:
        args += ["-Y", f"tcp.port == {port}"]
    for f in FIELDS:
        args += ["-e", f]

    records = []
    for line in _run_tshark(args).splitlines():
        if not line.strip():
            continue
        frame, stream, protocols, content_types, opaque_types, handshake_types, supported_versions, tcp_len = (
            line.split("|")
        )

        handshake = _int_list(handshake_types)
        content = _int_list(content_types) + _int_list(opaque_types)

        negotiated = None
        if SERVER_HELLO_TYPE in handshake and supported_versions:
            versions = _hex_list(supported_versions)
            negotiated = versions[0] if versions else None

        records.append(
            Record(
                frame=int(frame),
                stream=int(stream) if stream else None,
                protocol=protocols.split(":")[-1] if protocols else "",
                tls_content_types=content,
                tls_handshake_types=handshake,
                tls_negotiated_version=negotiated,
                payload_len=int(tcp_len) if tcp_len else 0,
            )
        )
    return records


def first_payload_frame(pcap: Path, port: int | None = None) -> tuple[int, int] | None:
    """Returns (frame number, byte offset of the first TCP payload byte) for the earliest frame
    carrying a non-empty TCP payload, or None if no frame has one."""
    filter_expr = "tcp.len > 0"
    if port is not None:
        filter_expr += f" and tcp.port == {port}"

    frame_numbers = [
        int(n) for n in _run_tshark(["-r", str(pcap), "-Y", filter_expr, "-T", "fields", "-e", "frame.number"]).split()
        if n
    ]
    if not frame_numbers:
        return None
    frame_number = frame_numbers[0]

    raw = _run_tshark(["-r", str(pcap), "-Y", f"frame.number == {frame_number}", "-T", "json", "-x"])
    layers = json.loads(raw)[0]["_source"]["layers"]
    payload_raw = layers.get("tcp", {}).get("tcp.payload_raw")
    if not payload_raw:
        return None
    return frame_number, int(payload_raw[1])


def classify(pcap: Path, port: int | None = None) -> dict[str, Any]:
    """Classifies the (single) session on `pcap` (optionally restricted to `port`) as one of:
    tls1.3 / tls1.2 / plaintext / unknown (TLS traffic without an observed ServerHello) /
    empty (no frames matched)."""
    records = parse_records(pcap, port=port)

    negotiated = next((r.tls_negotiated_version for r in records if r.tls_negotiated_version), None)
    if negotiated == TLS13_SUPPORTED_VERSION:
        return {"classification": "tls1.3", "negotiatedVersion": negotiated}

    server_hello_seen = any(SERVER_HELLO_TYPE in r.tls_handshake_types for r in records)
    if server_hello_seen:
        return {"classification": "tls1.2", "negotiatedVersion": None}

    has_tls = any(r.protocol == "tls" or r.tls_content_types or r.tls_handshake_types for r in records)
    if has_tls:
        return {"classification": "unknown"}

    offset_info = first_payload_frame(pcap, port=port)
    if offset_info is None:
        return {"classification": "empty"}
    frame_number, offset = offset_info
    return {"classification": "plaintext", "frame": frame_number, "payloadOffset": offset}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pcap", type=Path)
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument(
        "--classify", action="store_true", help="print one classification object instead of the full record list"
    )
    args = parser.parse_args(argv)

    if args.classify:
        print(json.dumps(classify(args.pcap, port=args.port)))
    else:
        records = parse_records(args.pcap, port=args.port)
        print(json.dumps([r.as_dict() for r in records], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
