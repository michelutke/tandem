#!/usr/bin/env bash
# Self-test for tools/harness/scenario-watchdog.sh (E23-09). Runs entirely locally, no Mac app.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WATCHDOG="$ROOT/tools/harness/scenario-watchdog.sh"
FAILURES=0

check() {
  local name="$1"
  local ok="$2"
  if [ "$ok" = "1" ]; then
    echo "ok: $name"
  else
    echo "FAIL: $name" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

run_script() {
  local body="$1"
  bash -c "source '$WATCHDOG'; trap 'echo cleanup-ran >&2' EXIT; $body" 2>&1
}

output="$(run_script 'scenario_begin fast 5; sleep 0.2; scenario_end; echo done')"
status=$?
check "scenarioEndsInTime_scriptCompletes" "$([ "$status" = 0 ] && [[ "$output" == *done* ]] && echo 1 || echo 0)"

start=$SECONDS
output="$(run_script 'scenario_begin stuck 1; sleep 30; echo unreachable')"
status=$?
elapsed=$((SECONDS - start))
check "scenarioHangsInSleep_exitsOneNamingScenario" \
  "$([ "$status" = 1 ] && [[ "$output" == *"scenario stuck exceeded"* ]] && [[ "$output" != *unreachable* ]] && echo 1 || echo 0)"
check "scenarioHangsInSleep_exitTrapRuns" "$([[ "$output" == *cleanup-ran* ]] && echo 1 || echo 0)"
check "scenarioHangsInSleep_abortsWithinLimitPlusGrace" "$([ "$elapsed" -lt 10 ] && echo 1 || echo 0)"

output="$(run_script 'scenario_begin fifo 1; mkfifo "$(mktemp -u)" 2>/dev/null; f=$(mktemp -u); mkfifo "$f"; exec 4<>"$f"; read -r line <&4; echo unreachable')"
status=$?
check "scenarioBlocksOnFifoRead_exitsOne" "$([ "$status" = 1 ] && [[ "$output" != *unreachable* ]] && echo 1 || echo 0)"

output="$(run_script 'scenario_begin first 1; scenario_begin second 5; sleep 2.5; scenario_end; echo done')"
status=$?
check "scenarioBeginReplacesPriorWatchdog_noStaleAbort" "$([ "$status" = 0 ] && [[ "$output" == *done* ]] && echo 1 || echo 0)"

[ "$FAILURES" -eq 0 ] || exit 1
echo "scenario-watchdog self-test OK"
