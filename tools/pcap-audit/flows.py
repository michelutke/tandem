#!/usr/bin/env python3
"""tools/pcap-audit/flows.py — E60-06: TCP flow audit for the control + media connection pair.

The media connection terminates on the same single Tandem port as the control connection (no second
listener), so one capture holds at least two distinct TCP flows on that port. This pass classifies
every TCP flow in the capture and fails if any flow is not TLS 1.3, if any flow targets a port other
than the Tandem port, or if fewer than `--min-flows` flows are seen on the Tandem port (so a pass is
never vacuous).

Usage:
    python3 flows.py <pcap> --port <port> [--min-flows <n>]

Exits 0 on pass, 1 on fail, with a JSON report on stdout.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import analyze


def list_flows(pcap: Path) -> dict[int, tuple[int, int]]:
    """Maps each TCP stream index to its (first source port, first destination port)."""
    args = ["-r", str(pcap), "-Y", "tcp", "-T", "fields", "-e", "tcp.stream", "-e", "tcp.srcport", "-e", "tcp.dstport"]
    flows: dict[int, tuple[int, int]] = {}
    for line in analyze._run_tshark(args).splitlines():
        stream, src, dst = line.split("\t")
        flows.setdefault(int(stream), (int(src), int(dst)))
    return flows


def classify_flow(records: list[analyze.Record]) -> str:
    server_hello = next((r for r in records if analyze.SERVER_HELLO_TYPE in r.tls_handshake_types), None)
    if server_hello is not None:
        return "tls1.3" if server_hello.tls_negotiated_version == analyze.TLS13_SUPPORTED_VERSION else "tls1.2"
    if any(r.payload_len > 0 and not r.tls_content_types and not r.tls_handshake_types for r in records):
        return "plaintext"
    return "unknown"


def audit_flows(pcap: Path, port: int, min_flows: int = 2) -> dict[str, Any]:
    flows = list_flows(pcap)
    by_stream: dict[int, list[analyze.Record]] = {}
    for record in analyze.parse_records(pcap):
        if record.stream is not None:
            by_stream.setdefault(record.stream, []).append(record)

    report = [
        {
            "stream": stream,
            "ports": list(ports),
            "classification": classify_flow(by_stream.get(stream, [])),
        }
        for stream, ports in sorted(flows.items())
    ]
    off_port = [f for f in report if port not in f["ports"]]
    if off_port:
        return {"result": "fail", "reason": "off-port-flow", "flows": off_port}
    not_tls13 = [f for f in report if f["classification"] != "tls1.3"]
    if not_tls13:
        return {"result": "fail", "reason": "non-tls13-flow", "flows": not_tls13}
    if len(report) < min_flows:
        return {"result": "fail", "reason": "too-few-flows", "flowCount": len(report), "minFlows": min_flows}
    return {"result": "pass", "flowCount": len(report), "flows": report}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pcap", type=Path)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--min-flows", type=int, default=2)
    args = parser.parse_args(argv)

    result = audit_flows(args.pcap, args.port, min_flows=args.min_flows)
    print(json.dumps(result))
    return 0 if result["result"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
