"""pytest suite for tools/pcap-audit/flows.py (E60-06 tdd entries).

tdd:
  unit: pcapAudit_fixtureTwoTlsFlowsOnOnePort_classifiesBothConnections
  security: pcapAudit_activeMirrorSession_onlyTls13RecordsOnBothConnections
  security: pcapAudit_activeMirrorSession_allTandemFlowsOnSinglePort

The two security entries run tools/harness/integration/e60-06.sh against the real Mac server app; they
need a Mac with BPF access and run in the jvm-harness workflow, so here they are opt-in via
TANDEM_E60_06_LIVE=1. flows.py's own pass/fail logic is covered by the unit tests below.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

import flows

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
TOOL = Path(__file__).resolve().parents[1] / "flows.py"
LIVE_SCRIPT = Path(__file__).resolve().parents[3] / "tools" / "harness" / "integration" / "e60-06.sh"
TWO_FLOWS = FIXTURES / "two-tls13-flows-one-port.pcapng"
TANDEM_PORT = 15444

live_only = pytest.mark.skipif(
    os.environ.get("TANDEM_E60_06_LIVE") != "1", reason="needs the real Mac server app and BPF; set TANDEM_E60_06_LIVE=1"
)


def test_pcapAudit_fixtureTwoTlsFlowsOnOnePort_classifiesBothConnections():
    result = flows.audit_flows(TWO_FLOWS, TANDEM_PORT)

    assert result["result"] == "pass"
    assert result["flowCount"] == 2
    assert {f["classification"] for f in result["flows"]} == {"tls1.3"}
    assert len({f["stream"] for f in result["flows"]}) == 2
    assert all(TANDEM_PORT in f["ports"] for f in result["flows"])


def test_pcapAudit_singleFlowCapture_failsAsVacuous():
    result = flows.audit_flows(FIXTURES / "tls13-handshake.pcapng", TANDEM_PORT)

    assert result["result"] == "fail"
    assert result["reason"] == "too-few-flows"


def test_pcapAudit_flowToOtherPort_failsNamingTheFlow():
    result = flows.audit_flows(TWO_FLOWS, TANDEM_PORT + 1)

    assert result["result"] == "fail"
    assert result["reason"] == "off-port-flow"
    assert len(result["flows"]) == 2


def test_pcapAudit_tls12Flow_fails():
    result = flows.audit_flows(FIXTURES / "tls12-handshake.pcapng", 15443, min_flows=1)

    assert result["result"] == "fail"
    assert result["reason"] == "non-tls13-flow"


def test_pcapAudit_plaintextFlow_fails():
    result = flows.audit_flows(FIXTURES / "plaintext-payload.pcapng", 15445, min_flows=1)

    assert result["result"] == "fail"
    assert result["flows"][0]["classification"] == "plaintext"


def test_pcapAudit_cli_exitStatusMatchesResult():
    ok = subprocess.run(
        [sys.executable, str(TOOL), str(TWO_FLOWS), "--port", str(TANDEM_PORT)], capture_output=True, text=True
    )
    assert ok.returncode == 0
    assert json.loads(ok.stdout)["result"] == "pass"

    failing = subprocess.run(
        [sys.executable, str(TOOL), str(TWO_FLOWS), "--port", "9"], capture_output=True, text=True
    )
    assert failing.returncode == 1


def test_pcapAudit_e60_06Script_isValidBash():
    assert subprocess.run(["bash", "-n", str(LIVE_SCRIPT)]).returncode == 0


@live_only
def test_pcapAudit_activeMirrorSession_onlyTls13RecordsOnBothConnections(tmp_path):
    assert subprocess.run([str(LIVE_SCRIPT), str(tmp_path / "e60-06.pcapng")]).returncode == 0


@live_only
def test_pcapAudit_activeMirrorSession_allTandemFlowsOnSinglePort(tmp_path):
    assert subprocess.run([str(LIVE_SCRIPT), str(tmp_path / "e60-06.pcapng")]).returncode == 0
