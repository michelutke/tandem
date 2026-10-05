"""pytest suite for tools/pcap-audit/media_volume.py and mirror-canary-audit.sh (E61-09 tdd entries).

tdd:
  security: pcapAudit_canaryOnMirroredScreen_zeroPlaintextOccurrences
  security: canaryProcedure_mirrorStep_captureContainsMediaTraffic

The two security entries run against a live phone + Mac mirror session (manual gate in
docs/testing/manual-gates.md); here the same audit logic is covered against committed fixture
pcaps, and the mirror step's planned adb commands by test_canary.py.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import media_volume

TOOL_DIR = Path(__file__).resolve().parents[1]
FIXTURES = TOOL_DIR / "fixtures"
AUDIT_SH = TOOL_DIR / "mirror-canary-audit.sh"
TANDEM_PORT = 15444
CLEAN_CANARY = "TANDEM-CANARY-ffffffffffffffffffffffffffffffff"
FIXTURE_CANARY = "TANDEM-CANARY-0123456789abcdef0123456789abcdef"


def _audit(pcap: Path, canary: str, port: int, min_bytes: int) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(AUDIT_SH), str(pcap), "--canary", canary, "--port", str(port), "--min-bytes", str(min_bytes)],
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_mediaVolume_fixtureHandshakeTraffic_countsPayloadBytes():
    result = media_volume.audit_volume(FIXTURES / "two-tls13-flows-one-port.pcapng", TANDEM_PORT, min_bytes=1)

    assert result["result"] == "pass"
    assert result["bytes"] > 0


def test_mediaVolume_handshakeOnlyCapture_failsBelowOneMegabyte():
    result = media_volume.audit_volume(FIXTURES / "two-tls13-flows-one-port.pcapng", TANDEM_PORT)

    assert result["result"] == "fail"
    assert result["reason"] == "too-little-media-traffic"
    assert result["minBytes"] == 1_000_000


def test_mediaVolume_otherPort_countsZeroBytes():
    result = media_volume.audit_volume(FIXTURES / "two-tls13-flows-one-port.pcapng", TANDEM_PORT + 1, min_bytes=1)

    assert result["result"] == "fail"
    assert result["bytes"] == 0


def test_mirrorCanaryAudit_noCanaryAndEnoughTraffic_exitsZero():
    result = _audit(FIXTURES / "two-tls13-flows-one-port.pcapng", CLEAN_CANARY, TANDEM_PORT, 1)

    assert result.returncode == 0, result.stdout + result.stderr
    assert json.loads(result.stdout.splitlines()[-1])["result"] == "pass"


def test_mirrorCanaryAudit_canaryInCapture_exitsNonZero():
    result = _audit(FIXTURES / "canary-single-payload.pcapng", FIXTURE_CANARY, TANDEM_PORT, 0)

    assert result.returncode != 0


def test_mirrorCanaryAudit_noMediaTraffic_exitsNonZero():
    result = _audit(FIXTURES / "two-tls13-flows-one-port.pcapng", CLEAN_CANARY, TANDEM_PORT, 1_000_000)

    assert result.returncode != 0
