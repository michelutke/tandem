"""pytest suite for tools/pcap-audit/canary.sh (E15-07 tdd entries).

tdd:
  unit: canaryScript_twoConsecutiveDryRuns_generateDistinctCanaries
  unit: canaryScript_phase1DryRun_plansOnlyDisplayNameStep
  unit: canaryScript_notificationStepDryRun_issuesCompanionCanaryBroadcast
  unit: canaryScript_featureDoneButStepDisabled_exitsNonZero

All four run `canary.sh --dry-run` (and variants) as a subprocess, no device or hardware touched --
`--dry-run` prints the planned steps and exact commands without dialing adb or the JVM harness.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
CANARY_SH = TOOL_DIR / "canary.sh"

CANARY_LINE_RE = re.compile(r"^CANARY: (TANDEM-CANARY-[0-9a-f]{32})$", re.MULTILINE)
NONCE_LINE_RE = re.compile(r"^NONCE: ([0-9a-f]{32})$", re.MULTILINE)


def _run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(CANARY_SH), *args],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_canaryScript_twoConsecutiveDryRuns_generateDistinctCanaries():
    first = _run("--dry-run")
    second = _run("--dry-run")

    assert first.returncode == 0, first.stderr
    assert second.returncode == 0, second.stderr

    first_canary = CANARY_LINE_RE.search(first.stdout).group(1)
    second_canary = CANARY_LINE_RE.search(second.stdout).group(1)

    assert first_canary != second_canary
    # 128 random bits -> 32 lowercase hex chars after the fixed prefix.
    assert re.fullmatch(r"TANDEM-CANARY-[0-9a-f]{32}", first_canary)
    assert re.fullmatch(r"TANDEM-CANARY-[0-9a-f]{32}", second_canary)


def test_canaryScript_phase1DryRun_plansOnlyDisplayNameStep():
    result = _run("--dry-run", "--phase1-only")

    assert result.returncode == 0, result.stderr
    assert "STEP phase1 enabled" in result.stdout
    assert "e15-07-canary-phase1.sh" in result.stdout
    assert "STEP notification skipped (--phase1-only)" in result.stdout
    assert "STEP clipboard skipped (--phase1-only)" in result.stdout
    assert "STEP file skipped (--phase1-only)" in result.stdout
    # No later-phase command is planned when only phase1 is in scope.
    assert "adb shell" not in result.stdout


def test_canaryScript_notificationStepDryRun_issuesCompanionCanaryBroadcast():
    result = _run("--dry-run")

    assert result.returncode == 0, result.stderr
    nonce = NONCE_LINE_RE.search(result.stdout).group(1)

    assert "STEP notification enabled" in result.stdout
    expected_cmd = (
        f"CMD adb shell am broadcast -a dev.tandem.companion.POST --es kind canary --es nonce {nonce}"
    )
    assert expected_cmd in result.stdout


def test_canaryScript_featureDoneButStepDisabled_exitsNonZero():
    # E30 (notifications) and E31-06 (share target) are both shipped in this repo already, so
    # asking canary.sh to skip either one's step must fail, not silently skip it.
    disable_e30 = _run("--dry-run", "--disable-e30")
    disable_e31_06 = _run("--dry-run", "--disable-e31-06")

    assert disable_e30.returncode != 0
    assert disable_e31_06.returncode != 0

    # E40-11 (file share target) is not built yet -- forcing its step on must also fail, since the
    # feature it would exercise does not exist.
    enable_e40_11 = _run("--dry-run", "--enable-e40-11")
    assert enable_e40_11.returncode != 0


def test_canaryScript_mirrorStepDryRun_typesCanaryIntoCompanionActivity():
    result = _run("--dry-run")

    assert result.returncode == 0, result.stderr
    canary = CANARY_LINE_RE.search(result.stdout).group(1)
    assert "STEP mirror enabled" in result.stdout
    assert "CMD adb shell am start -n dev.tandem.companion/.InputCounterActivity" in result.stdout
    assert f"CMD adb shell input text {canary}" in result.stdout


def test_canaryScript_mirrorStepDisabledAfterE61_09Done_exitsNonZero():
    assert _run("--dry-run", "--disable-e61-09").returncode != 0
    phase1_only = _run("--dry-run", "--phase1-only")
    assert "STEP mirror skipped (--phase1-only)" in phase1_only.stdout
