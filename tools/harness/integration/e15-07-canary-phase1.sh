#!/usr/bin/env bash
# E15-07 Phase 1 (automated): pairs the real E15-15 JVM harness client with the real Mac app
# (tools/harness/mac-driver.sh) using a caller-supplied canary string as the JVM client's
# `--display-name` -- fed through the production `DeviceInfoProvider` into a genuine
# `PairRequest.deviceInfo.displayName` during a real pairing, then restarts both processes and
# reconnects, all inside one whole-interface tshark capture. There is no test-only wire payload or
# debug channel: the canary only ever travels through the same production pairing path a real
# display name would (backlog E15-07 notes, cycle 2 decision).
#
# The capture has no port filter (tools/pcap-audit's canary-run convention: the whole interface,
# not just the Tandem port) so canary_scan.py can prove the canary appears nowhere on the wire,
# not merely off the Tandem port.
#
# Usage: e15-07-canary-phase1.sh <canary-string> <out.pcapng>
# Exit 0: pairing + restart-reconnect both succeeded AND canary_scan.py found 0 occurrences.
# Exit 1: any step failed, or the canary was found in the capture.
set -uo pipefail

E15_07_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E15_07_ROOT/android"
PCAP_AUDIT_DIR="$E15_07_ROOT/tools/pcap-audit"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
TSHARK="${TSHARK_BIN:-tshark}"
STARTUP_TIMEOUT_SECONDS=10
PAIR_TIMEOUT_SECONDS=10
LOG_WAIT_TIMEOUT_SECONDS=10
CONNECT_TIMEOUT_SECONDS=5

CANARY="${1:-}"
OUT_PCAP="${2:-}"
if [ -z "$CANARY" ] || [ -z "$OUT_PCAP" ]; then
  echo "usage: $0 <canary-string> <out.pcapng>" >&2
  exit 2
fi

# shellcheck source=../mac-driver.sh
source "$E15_07_ROOT/tools/harness/mac-driver.sh"

E15_07_TMP_DIR=""
E15_07_CLASSPATH=""
CLIENT_PID=""
TSHARK_PID=""
TSHARK_LOG=""

log() { echo "e15-07-canary-phase1: $*" >&2; }

cleanup() {
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    kill "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
  fi
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  if [ -n "$TSHARK_PID" ] && kill -0 "$TSHARK_PID" 2>/dev/null; then
    kill -INT "$TSHARK_PID" 2>/dev/null || true
    wait "$TSHARK_PID" 2>/dev/null || true
  fi
  [ -n "$TSHARK_LOG" ] && rm -f "$TSHARK_LOG"
  harness_cleanup
  if [ -n "$E15_07_TMP_DIR" ] && [ -d "$E15_07_TMP_DIR" ]; then
    rm -rf "$E15_07_TMP_DIR"
  fi
}
trap cleanup EXIT

if [ "$(uname)" != "Darwin" ]; then
  log "FAIL: this integration test requires the real macOS pairing window/listener -- not skipping"
  exit 1
fi

# Waits (up to $2 seconds, default $LOG_WAIT_TIMEOUT_SECONDS) for a line matching regex $1 to
# appear in the current launch's log; prints the last matching line and returns 0, or returns 1 on
# timeout.
wait_for_log_line() {
  local pattern="$1"
  local timeout="${2:-$LOG_WAIT_TIMEOUT_SECONDS}"
  local waited=0
  while (( waited < timeout * 10 )); do
    local match
    match="$(grep -o "$pattern" "$HARNESS_LOG_PATH" 2>/dev/null | tail -1)"
    if [ -n "$match" ]; then
      printf '%s\n' "$match"
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

start_client() {
  local identity_file="$1"
  local in_fifo="$2"
  local out_fifo="$3"
  mkfifo "$in_fifo" "$out_fifo"
  "$JAVA_BIN" -cp "$E15_07_CLASSPATH" "$JVM_MAIN_CLASS" \
    --identity-file "$identity_file" --display-name "$CANARY" \
    <"$in_fifo" >"$out_fifo" 2>&1 &
  CLIENT_PID=$!
}

wait_for_line_prefix() {
  local prefix="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))
  local line=""
  while (( SECONDS < deadline )); do
    local remaining=$((deadline - SECONDS))
    [ "$remaining" -lt 1 ] && remaining=1
    if ! IFS= read -r -t "$remaining" line <&4; then
      printf '%s\n' "$line"
      return 1
    fi
    case "$line" in
      "$prefix"*)
        printf '%s\n' "$line"
        return 0
        ;;
      *)
        log "jvm-client: $line"
        ;;
    esac
  done
  printf '%s\n' "$line"
  return 1
}

log "resolving JVM harness client runtime classpath (build once)"
if ! E15_07_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not build/resolve the jvm-client runtime classpath"
  exit 1
fi
E15_07_CLASSPATH="${E15_07_CLASSPATH%:}"

E15_07_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e15-07.XXXXXX")"

log "building the real Mac app (build once)"
if ! harness_init; then
  log "FAIL: Mac app build failed"
  exit 1
fi

MAC_PORT=$(( (RANDOM % 20000) + 20000 ))

log "starting whole-interface capture (no port filter, canary-run convention): $OUT_PCAP"
TSHARK_LOG="$(mktemp)"
"$TSHARK" -i lo0 -w "$OUT_PCAP" 2>"$TSHARK_LOG" &
TSHARK_PID=$!
for _ in $(seq 1 150); do
  grep -q "Capturing on" "$TSHARK_LOG" 2>/dev/null && break
  kill -0 "$TSHARK_PID" 2>/dev/null || break
  sleep 0.1
done
sleep 0.5

FAILED=0

# --- pair via the QR URI, JVM client display name set to the canary ----------------------------

log "launching Mac app with a real pairing window open"
harness_launch "$MAC_PORT" -HarnessOpenPairingWindow YES -HarnessAutoConfirmPairing YES
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came up on port $MAC_PORT"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  QR_LINE="$(wait_for_log_line 'harness-pairing-qr-uri: .*')" || {
    log "FAIL: Mac app never printed its pairing QR URI"
    cat "$HARNESS_LOG_PATH" >&2
    FAILED=1
  }
fi

if [ "$FAILED" -eq 0 ]; then
  QR_URI="${QR_LINE#harness-pairing-qr-uri: }"
  CLIENT_IDENTITY="$E15_07_TMP_DIR/jvm-client-identity.bin"
  start_client "$CLIENT_IDENTITY" "$E15_07_TMP_DIR/client.in" "$E15_07_TMP_DIR/client.out"
  exec 3>"$E15_07_TMP_DIR/client.in"
  exec 4<"$E15_07_TMP_DIR/client.out"

  client_startup="$(wait_for_line_prefix "harness-identity-spki: " "$STARTUP_TIMEOUT_SECONDS")"
  case "$client_startup" in
    "harness-identity-spki: "*) ;;
    *)
      log "FAIL: JVM client never printed its startup identity line: $client_startup"
      FAILED=1
      ;;
  esac
fi

if [ "$FAILED" -eq 0 ]; then
  echo "PAIR $QR_URI" >&3
  response="$(wait_for_line_prefix "OK PAIRING_STARTED" "$STARTUP_TIMEOUT_SECONDS")"
  if [ "$response" != "OK PAIRING_STARTED" ]; then
    log "FAIL: PAIR command did not start pairing: $response"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  event="$(wait_for_line_prefix "EVENT AwaitingUserConfirm(" "$PAIR_TIMEOUT_SECONDS")"
  case "$event" in
    "EVENT AwaitingUserConfirm("*) ;;
    *)
      log "FAIL: JVM client never reached AwaitingUserConfirm: $event"
      FAILED=1
      ;;
  esac
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONFIRM" >&3
  CONFIRMED_OK=""
  PAIRED_EVENT=""
  confirm_deadline=$((SECONDS + STARTUP_TIMEOUT_SECONDS + PAIR_TIMEOUT_SECONDS))
  while (( SECONDS < confirm_deadline )) && { [ -z "$CONFIRMED_OK" ] || [ -z "$PAIRED_EVENT" ]; }; do
    remaining=$((confirm_deadline - SECONDS))
    [ "$remaining" -lt 1 ] && remaining=1
    if ! IFS= read -r -t "$remaining" line <&4; then
      break
    fi
    case "$line" in
      "OK CONFIRMED") CONFIRMED_OK="$line" ;;
      "EVENT PAIRED "*) PAIRED_EVENT="$line" ;;
      *) log "jvm-client: $line" ;;
    esac
  done
  if [ -z "$CONFIRMED_OK" ] || [ -z "$PAIRED_EVENT" ]; then
    log "FAIL: CONFIRM did not commit trust on both sides"
    FAILED=1
  else
    MAC_FP_B64="$(printf '%s' "$PAIRED_EVENT" | awk '{print $NF}')"
    log "OK: paired with the canary display name; trust committed on both sides"
  fi
fi

# --- restart both processes, reconnect using only the persisted trust store ---------------------

if [ "$FAILED" -eq 0 ]; then
  echo "EXIT" >&3 2>/dev/null || true
  exec 3>&-
  exec 4<&-
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    wait "$CLIENT_PID" 2>/dev/null
  fi
  CLIENT_PID=""

  harness_kill
  log "relaunching Mac app (plain -- no pairing window) against the same keychain"
  harness_launch "$MAC_PORT"
  if ! harness_wait_for_listening "$MAC_PORT"; then
    log "FAIL: Mac listener never came back up after restart"
    cat "$HARNESS_LOG_PATH" >&2
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  start_client "$CLIENT_IDENTITY" "$E15_07_TMP_DIR/client2.in" "$E15_07_TMP_DIR/client2.out"
  exec 3>"$E15_07_TMP_DIR/client2.in"
  exec 4<"$E15_07_TMP_DIR/client2.out"

  client2_startup="$(wait_for_line_prefix "harness-identity-spki: " "$STARTUP_TIMEOUT_SECONDS")"
  case "$client2_startup" in
    "harness-identity-spki: "*) ;;
    *)
      log "FAIL: relaunched JVM client never printed its startup identity line: $client2_startup"
      FAILED=1
      ;;
  esac
  if [ "$FAILED" -eq 0 ] && [ "$client2_startup" != "$client_startup" ]; then
    log "FAIL: relaunched JVM client identity changed ($client2_startup != $client_startup)"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  response="$(wait_for_line_prefix "OK CONNECTED" "$CONNECT_TIMEOUT_SECONDS")"
  if [ "$response" != "OK CONNECTED" ]; then
    log "FAIL: reconnect expected OK CONNECTED, got: $response"
    FAILED=1
  else
    log "OK: reconnect reached Ready using only the persisted trust store"
  fi
  echo "EXIT" >&3 2>/dev/null || true
  exec 3>&-
  exec 4<&-
fi

# Let the last frames (closing FINs, the reconnect's own handshake) land before tshark stops.
sleep 1
if [ -n "$TSHARK_PID" ] && kill -0 "$TSHARK_PID" 2>/dev/null; then
  kill -INT "$TSHARK_PID" 2>/dev/null || true
  wait "$TSHARK_PID" 2>/dev/null || true
fi
TSHARK_PID=""

if [ "$FAILED" -ne 0 ]; then
  log "e15-07 Phase 1 pairing/reconnect FAILED -- not scanning the capture"
  exit 1
fi

log "scanning capture for canary occurrences: $OUT_PCAP"
if ! scan_output="$(python3 "$PCAP_AUDIT_DIR/canary_scan.py" "$OUT_PCAP" --canary "$CANARY")"; then
  log "FAIL: canary found in capture: $scan_output"
  exit 1
fi
log "OK: 0 canary occurrences in capture ($scan_output)"
exit 0
