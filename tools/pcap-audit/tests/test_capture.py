"""pytest suite for tools/pcap-audit/capture.sh (E15-04 tdd entries).

tdd:
  unit: pcapCapture_localhostTrafficOnTwoPorts_recordsOnlyTandemPort

Drives real loopback TCP traffic on two ports while capture.sh runs, filtered to only one of
them, then asserts the resulting pcap contains 100% of the Tandem-port traffic (the payload sent
on it) and 0 frames from the other port. Requires tshark to be able to capture on lo0 without
elevated privileges (see tools/pcap-audit/README.md); skips if it cannot.
"""

from __future__ import annotations

import socket
import subprocess
import tempfile
import textwrap
import threading
from pathlib import Path

import pytest

TOOL_DIR = Path(__file__).resolve().parents[1]
CAPTURE_SH = TOOL_DIR / "capture.sh"

TANDEM_PAYLOAD = b"TANDEM-PORT-PAYLOAD"
OTHER_PAYLOAD = b"OTHER-PORT-PAYLOAD"


def _can_capture_on_lo0() -> bool:
    with tempfile.TemporaryDirectory() as tmp:
        probe = subprocess.run(
            ["tshark", "-i", "lo0", "-a", "duration:1", "-w", str(Path(tmp) / "probe.pcapng")],
            capture_output=True,
            text=True,
            timeout=10,
        )
    return probe.returncode == 0


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _accept_one(port: int, received: list[bytes], ready: threading.Event) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", port))
        srv.listen(1)
        srv.settimeout(10)
        ready.set()
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            return
        with conn:
            conn.settimeout(5)
            chunks = []
            try:
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
            except socket.timeout:
                pass
            received.append(b"".join(chunks))


@pytest.mark.skipif(not _can_capture_on_lo0(), reason="tshark cannot capture on lo0 in this environment")
def test_pcapCapture_localhostTrafficOnTwoPorts_recordsOnlyTandemPort(tmp_path):
    tandem_port = _free_port()
    other_port = _free_port()
    out = tmp_path / "capture.pcapng"

    tandem_received: list[bytes] = []
    other_received: list[bytes] = []
    tandem_ready = threading.Event()
    other_ready = threading.Event()

    tandem_thread = threading.Thread(target=_accept_one, args=(tandem_port, tandem_received, tandem_ready))
    other_thread = threading.Thread(target=_accept_one, args=(other_port, other_received, other_ready))
    tandem_thread.start()
    other_thread.start()
    assert tandem_ready.wait(5)
    assert other_ready.wait(5)

    driver = tmp_path / "driver.py"
    driver.write_text(
        textwrap.dedent(
            f"""
            import socket

            s = socket.create_connection(("127.0.0.1", {tandem_port}))
            s.sendall({TANDEM_PAYLOAD!r})
            s.close()

            o = socket.create_connection(("127.0.0.1", {other_port}))
            o.sendall({OTHER_PAYLOAD!r})
            o.close()
            """
        )
    )

    result = subprocess.run(
        [
            "bash",
            str(CAPTURE_SH),
            "--port",
            str(tandem_port),
            "--out",
            str(out),
            "--iface",
            "lo0",
            "--script",
            "--",
            "python3",
            str(driver),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )

    tandem_thread.join(timeout=10)
    other_thread.join(timeout=10)

    assert result.returncode == 0, result.stderr
    assert out.exists()

    ports_output = subprocess.run(
        ["tshark", "-r", str(out), "-T", "fields", "-e", "tcp.port", "-E", "occurrence=a", "-E", "separator=,"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    seen_ports = {p for line in ports_output.splitlines() for p in line.split(",") if p}

    assert str(tandem_port) in seen_ports
    assert str(other_port) not in seen_ports

    payload_output = subprocess.run(
        ["tshark", "-r", str(out), "-T", "fields", "-e", "tcp.payload"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.replace(":", "").replace("\n", "")

    assert TANDEM_PAYLOAD.hex() in payload_output
    assert OTHER_PAYLOAD.hex() not in payload_output
    assert tandem_received == [TANDEM_PAYLOAD]
    assert other_received == [OTHER_PAYLOAD]
