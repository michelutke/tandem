#!/usr/bin/env python3
"""tools/pcap-audit/canary_scan.py — E15-06: canary string scan across the full capture.

Scans a supplied ASCII canary string (`TANDEM-CANARY-<random>`) over (a) the raw bytes of every
frame in the capture, on any port, headers included, and (b) every reassembled TCP stream, so a
canary split across two TCP segments is still found. There is no port filter: the capture filter
for canary runs is the whole interface, not only the Tandem port, and this tool never restricts
its scan to a single port either.

Usage:
    python3 canary_scan.py <pcap> --canary <string>

Exits 0 if the canary is found nowhere, 1 otherwise (with a JSON report on stdout naming the
occurrence count, the frame(s) it was found in directly, and any TCP stream(s) where it was only
recoverable via reassembly).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from analyze import TSHARK


def _run_tshark(args: list[str]) -> str:
    result = subprocess.run([TSHARK, *args], capture_output=True, text=True, check=True)
    return result.stdout


def _frame_raw_bytes(pcap: Path) -> list[tuple[int, bytes]]:
    """Returns (frame number, full raw frame bytes incl. link/IP/TCP headers) for every frame."""
    raw = _run_tshark(["-r", str(pcap), "-T", "json", "-x"])
    frames = []
    for entry in json.loads(raw):
        layers = entry["_source"]["layers"]
        frame_number = int(layers["frame"]["frame.number"])
        frame_hex = layers["frame_raw"][0]
        frames.append((frame_number, bytes.fromhex(frame_hex)))
    return frames


def _tcp_streams(pcap: Path) -> list[int]:
    raw = _run_tshark(["-r", str(pcap), "-T", "fields", "-e", "tcp.stream", "-E", "occurrence=a"])
    streams: set[int] = set()
    for line in raw.splitlines():
        for value in line.split(","):
            if value:
                streams.add(int(value))
    return sorted(streams)


def _stream_frame_numbers(pcap: Path, stream: int) -> list[int]:
    raw = _run_tshark(
        ["-r", str(pcap), "-Y", f"tcp.stream == {stream}", "-T", "fields", "-e", "frame.number"]
    )
    return [int(n) for n in raw.split() if n]


def _reassembled_stream_bytes(pcap: Path, stream: int) -> bytes:
    raw = _run_tshark(["-r", str(pcap), "-q", "-z", f"follow,tcp,raw,{stream}"])
    hex_chunks = [
        line.strip()
        for line in raw.splitlines()
        if line.strip() and all(c in "0123456789abcdefABCDEF" for c in line.strip())
    ]
    return bytes.fromhex("".join(hex_chunks))


def scan_for_canary(pcap: Path, canary: str) -> dict[str, Any]:
    canary_bytes = canary.encode("ascii")

    frame_hits = sorted(
        frame_number
        for frame_number, raw in _frame_raw_bytes(pcap)
        if canary_bytes in raw
    )

    stream_hits = []
    for stream in _tcp_streams(pcap):
        stream_frames = _stream_frame_numbers(pcap, stream)
        if any(f in frame_hits for f in stream_frames):
            continue  # already reported at the frame level
        if canary_bytes in _reassembled_stream_bytes(pcap, stream):
            stream_hits.append({"stream": stream, "frames": stream_frames})

    occurrences = len(frame_hits) + len(stream_hits)
    if occurrences == 0:
        return {"result": "pass", "occurrences": 0}

    return {
        "result": "fail",
        "occurrences": occurrences,
        "frameHits": frame_hits,
        "streamHits": stream_hits,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pcap", type=Path)
    parser.add_argument("--canary", required=True, help="ASCII canary string to search for")
    args = parser.parse_args(argv)

    result = scan_for_canary(args.pcap, args.canary)
    print(json.dumps(result))
    return 0 if result["result"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
