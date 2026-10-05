#!/usr/bin/env bash
# E62-08 (integration variant): the real Mac server app sends an `InputEvent` to a paired JVM harness
# client that has no mirror session; the client's real `InputGate` (E62-06) in front of a recording
# dispatcher (`INPUTWATCH`/`INPUTSTATS`, `RemoteInputHarness.kt`) must produce zero dispatcher calls
# and exactly one drop record per event (`inputGate_realMacSendsInputWithoutSession_zeroDispatchOneDropRecord`).
# A `SetText` event carries a canary; log-audit (E15-17) over the client's captured output and the Mac
# log must find zero occurrences (`logAudit_droppedSetTextCanary_absentFromLogs`).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../mitm-lab/e62-08-input-auth/lib/e62-08-common.sh
source "$SCRIPT_DIR/../../mitm-lab/e62-08-input-auth/lib/e62-08-common.sh"
trap e15_10_teardown EXIT

CAPTURE=""
FAILED=0

# $1=command. Sends it to the JVM client, appends the exchange to $CAPTURE and prints the reply.
client() {
  local reply
  e15_10_send "$1"
  reply="$(e15_10_read "$E15_10_RAWOPEN_TIMEOUT_SECONDS")" || reply="ERROR NO_RESPONSE"
  printf '> %s\n< %s\n' "$1" "$reply" >> "$CAPTURE"
  printf '%s\n' "$reply"
}

# $1=expected number of drop records. Polls INPUTSTATS until it reports them; prints the final line.
wait_for_drops() {
  local waited=0 line=""
  while (( waited < E62_08_STATS_TIMEOUT_SECONDS * 5 )); do
    line="$(client INPUTSTATS)"
    case "$line" in *" DROPS=$1 "*) break ;; esac
    sleep 0.2
    waited=$((waited + 1))
  done
  printf '%s\n' "$line"
}

e15_10_setup_jvm
e15_10_setup_mac
e15_10_start_client "phone-identity.bin"
e15_10_seed_trust "$CLIENT_SPKI_HEX" "E62-08 paired phone" "$E15_10_TMP_DIR/seed-phone.json"
PORT="$(e15_10_free_port)"
e62_08_launch_mac "$PORT"
MAC_FP_B64="$(e15_10_hex_to_b64url "$(harness_identity_spki)")"
CAPTURE="$E15_10_TMP_DIR/client-capture.log"
: > "$CAPTURE"
CANARY="$(e62_08_new_canary)"

[ "$(client "CONNECT 127.0.0.1 $PORT $MAC_FP_B64")" = "OK CONNECTED" ] || { e62_08_log "FAIL: CONNECT"; exit 1; }
[ "$(client INPUTWATCH)" = "OK INPUT_WATCHING" ] || { e62_08_log "FAIL: INPUTWATCH"; exit 1; }

e62_08_send_input "$CLIENT_SPKI_HEX" TAP 1 1 RANDOM || FAILED=1
stats="$(wait_for_drops 1)"
e62_08_log "after TAP with no mirror session: $stats"
case "$stats" in
  "OK INPUT DISPATCHER_CALLS=0 DROPS=1 RATE_LIMITED=0 LAST_DROP=NoConsent:TAP") ;;
  *) e62_08_log "FAIL: expected zero dispatcher calls and one NoConsent drop"; FAILED=1 ;;
esac

e62_08_send_input "$CLIENT_SPKI_HEX" SETTEXT 1 1 RANDOM "$CANARY" || FAILED=1
stats="$(wait_for_drops 2)"
e62_08_log "after SetText canary: $stats"
case "$stats" in
  "OK INPUT DISPATCHER_CALLS=0 DROPS=2 RATE_LIMITED=0 LAST_DROP=NoConsent:SET_TEXT") ;;
  *) e62_08_log "FAIL: expected zero dispatcher calls and two drops"; FAILED=1 ;;
esac

cat "$E15_10_TMP_DIR"/*.stderr.log >> "$CAPTURE" 2>/dev/null || true
if e62_08_log_audit "$CANARY" "$CAPTURE" "$HARNESS_LOG_PATH"; then
  e62_08_log "OK: log-audit found zero canary occurrences"
else
  e62_08_log "FAIL: canary found in captured logs"
  FAILED=1
fi

e15_10_assert_mac_alive "$PORT" || FAILED=1
if [ "$FAILED" -eq 0 ]; then
  e62_08_log "PASS"
  exit 0
fi
exit 1
