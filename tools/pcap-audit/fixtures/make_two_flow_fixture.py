#!/usr/bin/env python3
"""Builds two-tls13-flows-one-port.pcapng from tls13-handshake.pcapng (E60-06): the same real TLS 1.3
handshake twice on one server port, the second copy with its client port rewritten (TCP checksums are
left stale; tshark does not verify them by default). Usage: make_two_flow_fixture.py <fixtures-dir>"""

import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

LOOPBACK_HEADER_BYTES = 4
CLIENT_PORT_SHIFT = 1


def rewrite_client_port(classic_pcap: bytes, server_port: int) -> bytes:
    out = bytearray(classic_pcap[:24])
    offset = 24
    while offset < len(classic_pcap):
        header = classic_pcap[offset : offset + 16]
        captured = struct.unpack("<I", header[8:12])[0]
        packet = bytearray(classic_pcap[offset + 16 : offset + 16 + captured])
        ip_header_bytes = (packet[LOOPBACK_HEADER_BYTES] & 0x0F) * 4
        tcp = LOOPBACK_HEADER_BYTES + ip_header_bytes
        for port_offset in (tcp, tcp + 2):
            port = struct.unpack(">H", packet[port_offset : port_offset + 2])[0]
            if port != server_port:
                packet[port_offset : port_offset + 2] = struct.pack(">H", port + CLIENT_PORT_SHIFT)
        out += header + packet
        offset += 16 + captured
    return bytes(out)


def main() -> None:
    fixtures = Path(sys.argv[1])
    server_port = 15444
    with tempfile.TemporaryDirectory() as work:
        classic = os.path.join(work, "flow-a.pcap")
        subprocess.run(
            ["editcap", "-F", "pcap", str(fixtures / "tls13-handshake.pcapng"), classic], check=True
        )
        shifted = os.path.join(work, "flow-b.pcap")
        Path(shifted).write_bytes(rewrite_client_port(Path(classic).read_bytes(), server_port))
        subprocess.run(
            ["mergecap", "-w", str(fixtures / "two-tls13-flows-one-port.pcapng"), classic, shifted], check=True
        )


if __name__ == "__main__":
    main()
