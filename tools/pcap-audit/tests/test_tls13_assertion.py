"""pytest suite for tools/pcap-audit/tls13_assertion.py (E15-05 tdd entries).

tdd:
  unit: tls13Assertion_singlePlaintextPayload_exitsOneWithFrameAndOffset
  unit: tls13Assertion_tls12SessionFixture_exitsOneNamingVersion
  unit: tls13Assertion_onlyTls13Records_exitsZero
  security: pcapAudit_jvmHarnessPairAndReconnect_zeroNonTls13Records
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

import tls13_assertion

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
TOOL = Path(__file__).resolve().parents[1] / "tls13_assertion.py"

# E15-05 depends on E15-15 (the JVM-client-against-real-Mac-server harness) for this scenario;
# E15-15 (and the E15-21 JVM client it joins) are not implemented yet in this repo (only the
# E15-22 Mac driver at tools/harness/mac-driver.sh exists so far). Once E15-15 lands, this should
# drive a real pairing + restart-reconnect session through the harness, capture it with
# capture.sh, and feed the capture to assert_only_tls13 instead of skipping. See
# tools/pcap-audit/README.md.
JVM_HARNESS_SCRIPT = Path(__file__).resolve().parents[3] / "harness" / "jvm-harness.sh"


def test_tls13Assertion_singlePlaintextPayload_exitsOneWithFrameAndOffset():
    result = tls13_assertion.assert_only_tls13(FIXTURES / "plaintext-payload.pcapng")

    assert result["result"] == "fail"
    assert result["reason"] == "plaintext"
    assert result["frame"] > 0
    assert result["payloadOffset"] > 0


def test_tls13Assertion_tls12SessionFixture_exitsOneNamingVersion():
    result = tls13_assertion.assert_only_tls13(FIXTURES / "tls12-handshake.pcapng")

    assert result["result"] == "fail"
    assert result["reason"] == "tls1.2"
    assert result["negotiatedVersion"] is not None
    assert result["negotiatedVersion"] != "0x0304"


def test_tls13Assertion_onlyTls13Records_exitsZero():
    result = tls13_assertion.assert_only_tls13(FIXTURES / "tls13-handshake.pcapng")

    assert result == {"result": "pass", "recordCount": result["recordCount"]}
    assert result["recordCount"] > 0


def test_tls13Assertion_cli_exitStatusMatchesResult():
    ok = subprocess.run(
        [sys.executable, str(TOOL), str(FIXTURES / "tls13-handshake.pcapng")],
        capture_output=True,
        text=True,
    )
    assert ok.returncode == 0

    failing = subprocess.run(
        [sys.executable, str(TOOL), str(FIXTURES / "plaintext-payload.pcapng")],
        capture_output=True,
        text=True,
    )
    assert failing.returncode == 1


@pytest.mark.skipif(
    not JVM_HARNESS_SCRIPT.exists(),
    reason="E15-15 JVM harness (tools/harness/jvm-harness.sh) not implemented yet; see README",
)
def test_pcapAudit_jvmHarnessPairAndReconnect_zeroNonTls13Records(tmp_path):
    out = tmp_path / "jvm-harness-session.pcapng"
    subprocess.run(
        [
            "bash",
            str(Path(__file__).resolve().parents[1] / "capture.sh"),
            "--port",
            "7623",
            "--out",
            str(out),
            "--script",
            "--",
            "bash",
            str(JVM_HARNESS_SCRIPT),
            "pair-and-reconnect",
        ],
        check=True,
        timeout=900,
    )

    result = tls13_assertion.assert_only_tls13(out, port=7623)

    assert result == {"result": "pass", "recordCount": result["recordCount"]}
