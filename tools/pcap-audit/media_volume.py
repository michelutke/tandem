#!/usr/bin/env python3
"""tools/pcap-audit/media_volume.py — E61-09: media traffic volume check for the mirror canary window.

Sums the TCP payload bytes on the Tandem port and fails if they are below `--min-bytes` (default
1 MB), so a zero-occurrence canary scan over a capture with no real mirror traffic is never a
vacuous pass.

Usage:
    python3 media_volume.py <pcap> --port <port> [--min-bytes <n>]

Exits 0 on pass, 1 on fail, with a JSON report on stdout.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import analyze

DEFAULT_MIN_BYTES = 1_000_000


def port_payload_bytes(pcap: Path, port: int) -> int:
    args = ["-r", str(pcap), "-Y", f"tcp.port == {port} && tcp.len > 0", "-T", "fields", "-e", "tcp.len"]
    return sum(int(line) for line in analyze._run_tshark(args).splitlines() if line)


def audit_volume(pcap: Path, port: int, min_bytes: int = DEFAULT_MIN_BYTES) -> dict[str, Any]:
    total = port_payload_bytes(pcap, port)
    if total < min_bytes:
        return {"result": "fail", "reason": "too-little-media-traffic", "bytes": total, "minBytes": min_bytes}
    return {"result": "pass", "bytes": total, "minBytes": min_bytes}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pcap", type=Path)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--min-bytes", type=int, default=DEFAULT_MIN_BYTES)
    args = parser.parse_args(argv)

    result = audit_volume(args.pcap, args.port, min_bytes=args.min_bytes)
    print(json.dumps(result))
    return 0 if result["result"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
