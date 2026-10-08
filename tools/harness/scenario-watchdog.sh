#!/usr/bin/env bash
# Per-scenario deadline for harness integration scripts (E23-09). Source this file, then bracket
# each scenario with `scenario_begin <name> <limitSeconds>` / `scenario_end`. If a scenario is
# still running after its limit, the script logs a FAIL naming it and exits 1 (running the
# script's EXIT trap, after killing its child processes so a foreground blocker cannot defer the
# handler); if even that handler cannot run because the shell is stuck inside a
# blocking write, the script is SIGKILLed SCENARIO_KILL_GRACE_SECONDS later. No scenario can hang
# the script indefinitely.
SCENARIO_KILL_GRACE_SECONDS="${SCENARIO_KILL_GRACE_SECONDS:-5}"
SCENARIO_NAME=""
SCENARIO_WATCHDOG_PID=""
SCRIPT_PID=$$

scenario_deadline_exceeded() {
  echo "${SCENARIO_LOG_PREFIX:-harness}: FAIL: scenario ${SCENARIO_NAME} exceeded its deadline -- aborting" >&2
  exit 1
}
trap scenario_deadline_exceeded USR1

scenario_begin() {
  local name="$1"
  local limit_seconds="$2"
  scenario_end
  SCENARIO_NAME="$name"
  (
    sleep "$limit_seconds"
    local child
    for child in $(pgrep -P "$SCRIPT_PID"); do
      [ "$child" = "$BASHPID" ] || kill "$child" 2>/dev/null
    done
    kill -USR1 "$SCRIPT_PID" 2>/dev/null
    sleep "$SCENARIO_KILL_GRACE_SECONDS"
    kill -KILL "$SCRIPT_PID" 2>/dev/null
  ) >/dev/null 2>&1 &
  SCENARIO_WATCHDOG_PID=$!
}

scenario_end() {
  if [ -n "$SCENARIO_WATCHDOG_PID" ]; then
    kill "$SCENARIO_WATCHDOG_PID" 2>/dev/null
    wait "$SCENARIO_WATCHDOG_PID" 2>/dev/null
    SCENARIO_WATCHDOG_PID=""
  fi
}
