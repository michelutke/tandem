"""pytest suite for tools/pcap-audit/check-proto-schema.sh (E15-07 tdd entry).

tdd:
  ci: protoSchema_debugEchoOrTestMessageName_absent
"""

from __future__ import annotations

import subprocess
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = TOOL_DIR.parents[1]
CHECK_SH = TOOL_DIR / "check-proto-schema.sh"


def _run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(CHECK_SH), *args],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_protoSchema_debugEchoOrTestMessageName_absent():
    result = _run(str(REPO_ROOT / "protocol" / "proto"))
    assert result.returncode == 0, result.stdout + result.stderr


def test_protoSchema_fixtureWithDebugMessageName_exitsNonZero(tmp_path):
    (tmp_path / "bad.proto").write_text(
        'syntax = "proto3";\npackage tandem.v1;\nmessage DebugEcho {\n  bytes payload = 1;\n}\n'
    )

    result = _run(str(tmp_path))

    assert result.returncode == 1
    assert "DebugEcho" in result.stdout


def test_protoSchema_fixtureWithTestMessageName_exitsNonZero(tmp_path):
    (tmp_path / "bad.proto").write_text(
        'syntax = "proto3";\npackage tandem.v1;\nmessage FooTestPayload {\n  bytes payload = 1;\n}\n'
    )

    result = _run(str(tmp_path))

    assert result.returncode == 1
    assert "FooTestPayload" in result.stdout
