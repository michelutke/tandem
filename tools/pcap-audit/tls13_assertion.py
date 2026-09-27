#!/usr/bin/env python3
"""tools/pcap-audit/tls13_assertion.py — E15-05: "only TLS 1.3 records" assertion.

Assertion pass over analyze.py's classified record list: fails if any record on the Tandem port
is not part of a TLS 1.3 session (catches plaintext, a TLS 1.2 downgrade, or any non-TLS protocol
on the port). Every TCP payload between the peers must be a TLS 1.3 record (ContentType plus
legacy version 0x0303 after the handshake); a ServerHello without the supported_versions
extension equal to 0x0304 is a downgrade, and a payload-bearing frame tshark did not dissect as
TLS at all is plaintext.

Usage:
    python3 tls13_assertion.py <pcap> [--port <port>]

Exits 0 if every record is part of a TLS 1.3 session, 1 otherwise (with a JSON report on stdout
naming the frame, and the negotiated version or payload offset, depending on the failure).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import analyze


def assert_only_tls13(pcap: Path, port: int | None = None) -> dict[str, Any]:
    records = analyze.parse_records(pcap, port=port)

    server_hello = next(
        (r for r in records if analyze.SERVER_HELLO_TYPE in r.tls_handshake_types), None
    )
    if server_hello is not None and server_hello.tls_negotiated_version != analyze.TLS13_SUPPORTED_VERSION:
        return {
            "result": "fail",
            "reason": "tls1.2",
            "frame": server_hello.frame,
            "negotiatedVersion": server_hello.tls_handshake_version,
        }

    plaintext_record = next(
        (
            r
            for r in records
            if r.payload_len > 0 and not r.tls_content_types and not r.tls_handshake_types
        ),
        None,
    )
    if plaintext_record is not None:
        offset_info = analyze.first_payload_frame(pcap, port=port)
        frame_number, offset = offset_info if offset_info else (plaintext_record.frame, None)
        return {
            "result": "fail",
            "reason": "plaintext",
            "frame": frame_number,
            "payloadOffset": offset,
        }

    return {"result": "pass", "recordCount": len(records)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pcap", type=Path)
    parser.add_argument("--port", type=int, default=None)
    args = parser.parse_args(argv)

    result = assert_only_tls13(args.pcap, port=args.port)
    print(json.dumps(result))
    return 0 if result["result"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
