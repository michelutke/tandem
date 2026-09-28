#!/usr/bin/env bash
# E14-16: end-to-end QR pairing then reconnect after restarting both apps, on the E15-15/E12-13
# harness join -- the real Mac app under `tools/harness/mac-driver.sh` (D-75 file keychain, never
# the login keychain, never signed, built once) and the real JVM harness client CLI
# (`android/harness/jvm-client`, built once), talking real mTLS on 127.0.0.1/LAN only.
#
# Step 1 (acceptance #1): the Mac app is launched with `-HarnessOpenPairingWindow YES
# -HarnessAutoConfirmPairing YES` (E14-16's own DEBUG harness hooks, `TandemApp/HarnessHooks.swift`)
# -- opening a real `TandemPairing.PairingWindow`/`PairingCoordinator` and printing its QR URI --
# and the JVM client is driven through `PAIR <uri>` (reusing `core/pairing`'s real
# `PairingStateMachine`, exactly as production will).
#
# Step 2 (acceptance #7 and the trust-store acceptance): the confirmation code the JVM client
# computes (`EVENT AwaitingUserConfirm(code=...)`) must equal the one the Mac prints
# (`harness-pairing-confirmation-code: ...`) -- the Mac auto-confirms "Pair" the instant that code
# is computed (no owner-facing dialog exists yet, E14-11), so by the time the JVM client's own
# `CONFIRM` command commits its side, the Mac's trust store already holds exactly one record for
# the phone's identity (asserted via the new `-HarnessListTrust` one-shot hook).
#
# Step 3: both processes are killed and relaunched -- the Mac app plain (no pairing window: trust
# alone must carry the reconnect) against the same on-disk keychain, and the JVM client against the
# same `--identity-file` (E15-21's `PersistentIdentityKeyStore`) so its identity survives the
# restart. The JVM harness has no on-disk trust store of its own (E15-21 harness scope); this script
# stands in for it exactly as it already does for the phone's own production trust store, by
# reusing the Mac fingerprint `EVENT PAIRED` printed on the first run for the post-restart CONNECT.
#
# Step 4 (acceptance #2/#3): the reconnect must reach `OK CONNECTED` from a pinned `CONNECT` alone
# -- no `PAIR` involved -- and the relaunched Mac app's log must never print a pairing QR URI (its
# pairing window was never opened this run).
set -uo pipefail

E14_16_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E14_16_ROOT/android"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
STARTUP_TIMEOUT_SECONDS=10
PAIR_TIMEOUT_SECONDS=10
LOG_WAIT_TIMEOUT_SECONDS=10
CONNECT_TIMEOUT_SECONDS=5

# shellcheck source=../mac-driver.sh
source "$E14_16_ROOT/tools/harness/mac-driver.sh"

E14_16_TMP_DIR=""
E14_16_CLASSPATH=""
CLIENT_PID=""

log() { echo "e14-16: $*" >&2; }

cleanup() {
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    kill "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
  fi
  # Best-effort: fds may already be closed by the scenario that opened them.
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  harness_cleanup
  if [ -n "$E14_16_TMP_DIR" ] && [ -d "$E14_16_TMP_DIR" ]; then
    rm -rf "$E14_16_TMP_DIR"
  fi
}
trap cleanup EXIT

if [ "$(uname)" != "Darwin" ]; then
  log "FAIL: this integration test requires the real macOS pairing window/listener -- not skipping"
  exit 1
fi

base64url_to_hex() {
  local b64="$1"
  b64="${b64//-/+}"
  b64="${b64//_//}"
  case $(( ${#b64} % 4 )) in
    2) b64="${b64}==" ;;
    3) b64="${b64}=" ;;
  esac
  printf '%s' "$b64" | base64 -d | xxd -p -c 256 | tr -d '\n'
}

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

# Starts a fresh JVM harness client process with identity file $1, piped through fifos $2 (stdin) /
# $3 (stdout+stderr); sets $CLIENT_PID. Does not open either fifo end -- the caller does that so
# it can be re-run against a fresh pair of fifos across a restart.
start_client() {
  local identity_file="$1"
  local in_fifo="$2"
  local out_fifo="$3"
  mkfifo "$in_fifo" "$out_fifo"
  "$JAVA_BIN" -cp "$E14_16_CLASSPATH" "$JVM_MAIN_CLASS" --identity-file "$identity_file" \
    <"$in_fifo" >"$out_fifo" 2>&1 &
  CLIENT_PID=$!
}

# Reads one line from fd 4 (the client's stdout) with a bounded timeout; prints it and returns 0,
# or returns 1 on timeout/EOF.
read_response() {
  local timeout_seconds="$1"
  local line
  if IFS= read -r -t "$timeout_seconds" line <&4; then
    printf '%s\n' "$line"
    return 0
  fi
  return 1
}

# Reads lines from fd 4 until one starts with $1, skipping (and logging) anything else, for up to
# $2 seconds total; prints the matching (or last-read, on timeout/EOF) line.
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
if ! E14_16_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not build/resolve the jvm-client runtime classpath"
  exit 1
fi
E14_16_CLASSPATH="${E14_16_CLASSPATH%:}"

E14_16_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e14-16.XXXXXX")"

log "building the real Mac app (build once)"
if ! harness_init; then
  log "FAIL: Mac app build failed"
  exit 1
fi

MAC_PORT=$(( (RANDOM % 20000) + 20000 ))

# --- Step 1: pair via the QR URI with the JVM client --------------------------------------------

log "launching Mac app with a real pairing window open"
harness_launch "$MAC_PORT" -HarnessOpenPairingWindow YES -HarnessAutoConfirmPairing YES
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came up on port $MAC_PORT"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
fi

QR_LINE="$(wait_for_log_line 'harness-pairing-qr-uri: .*')" || {
  log "FAIL: Mac app never printed its pairing QR URI"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
}
QR_URI="${QR_LINE#harness-pairing-qr-uri: }"
log "OK: pairing QR URI printed"

CLIENT_IDENTITY="$E14_16_TMP_DIR/jvm-client-identity.bin"
start_client "$CLIENT_IDENTITY" "$E14_16_TMP_DIR/client.in" "$E14_16_TMP_DIR/client.out"
exec 3>"$E14_16_TMP_DIR/client.in"
exec 4<"$E14_16_TMP_DIR/client.out"

client_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: JVM client never printed its startup identity line"
  exit 1
}
case "$client_startup" in
  "harness-identity-spki: "*) ;;
  *)
    log "FAIL: JVM client unexpected startup line: $client_startup"
    exit 1
    ;;
esac
PHONE_FP_HEX="${client_startup#harness-identity-spki: }"

echo "PAIR $QR_URI" >&3
response="$(wait_for_line_prefix "OK PAIRING_STARTED" "$STARTUP_TIMEOUT_SECONDS")"
if [ "$response" != "OK PAIRING_STARTED" ]; then
  log "FAIL: PAIR command did not start pairing: $response"
  exit 1
fi
log "OK: QR pairing started on the JVM client"

# --- Step 2: assert the codes match and that trust is committed on both sides -------------------

event="$(wait_for_line_prefix "EVENT AwaitingUserConfirm(" "$PAIR_TIMEOUT_SECONDS")"
case "$event" in
  "EVENT AwaitingUserConfirm("*) ;;
  *)
    log "FAIL: JVM client never reached AwaitingUserConfirm: $event"
    exit 1
    ;;
esac
JVM_CODE="$(printf '%s' "$event" | sed -n 's/.*code=\([0-9]\{6\}\).*/\1/p')"
if [ -z "$JVM_CODE" ]; then
  log "FAIL: could not parse the JVM client's confirmation code from: $event"
  exit 1
fi

MAC_CODE_LINE="$(wait_for_log_line 'harness-pairing-confirmation-code: [0-9]\{6\}')" || {
  log "FAIL: Mac app never printed its confirmation code"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
}
MAC_CODE="${MAC_CODE_LINE#harness-pairing-confirmation-code: }"

if [ "$JVM_CODE" != "$MAC_CODE" ]; then
  log "FAIL: confirmation codes differ -- JVM client $JVM_CODE, Mac $MAC_CODE"
  exit 1
fi
log "OK: confirmation codes match ($JVM_CODE)"

echo "CONFIRM" >&3
# "OK CONFIRMED" and the two async EVENTs a successful `confirmCodesMatch()` produces (the
# explicit "EVENT PAIRED ..." trust-commit line, and the state collector's own "EVENT Paired") are
# all near-instantaneous local effects of the same call with no dependable ordering between them
# -- unlike the earlier "OK PAIRING_STARTED"/network-driven EVENTs above -- so both of the lines
# this step needs are collected from a single read loop rather than two sequential waits.
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
if [ -z "$CONFIRMED_OK" ]; then
  log "FAIL: CONFIRM command never confirmed"
  exit 1
fi
if [ -z "$PAIRED_EVENT" ]; then
  log "FAIL: JVM client never committed trust"
  exit 1
fi
MAC_FP_B64="$(printf '%s' "$PAIRED_EVENT" | awk '{print $NF}')"
log "OK: JVM client committed trust for the Mac's identity"

# Stop the Mac listener before reading its trust store (same concurrent-file-keychain-access
# concern `harness_seed_trust`/`harness_clear_trust` already document).
harness_kill
TRUST_RECORDS="$(harness_list_trust)"
TRUST_COUNT="$(printf '%s\n' "$TRUST_RECORDS" | grep -c '^harness-trust-record: ' || true)"
if [ "$TRUST_COUNT" -ne 1 ]; then
  log "FAIL: expected exactly one Mac trust record, found $TRUST_COUNT"
  printf '%s\n' "$TRUST_RECORDS" >&2
  exit 1
fi
MAC_TRUSTED_FP_HEX="$(printf '%s\n' "$TRUST_RECORDS" | sed -n 's/^harness-trust-record: //p')"
if [ "$MAC_TRUSTED_FP_HEX" != "$PHONE_FP_HEX" ]; then
  log "FAIL: Mac's trust record ($MAC_TRUSTED_FP_HEX) != the phone's own identity ($PHONE_FP_HEX)"
  exit 1
fi
log "OK: trust committed on both sides"

# --- Re-injection check (yaml acceptance "Re-injecting the same QR payload after success is ------
# rejected by the Mac", UC-03 same QR twice): the Mac's pairing window closed the instant it
# auto-confirmed above (single-use secret, `docs/planning/decisions.md` D-67/D-73) -- a brand new
# candidate connection replaying the exact same QR against the still-running Mac (before restart)
# must be rejected, never re-paired a second time.

log "re-injecting the same QR payload against the still-running Mac (must be rejected)"
FIRST_CLIENT_PID="$CLIENT_PID"
REINJECT_IDENTITY="$E14_16_TMP_DIR/reinject-identity.bin"
start_client "$REINJECT_IDENTITY" "$E14_16_TMP_DIR/reinject.in" "$E14_16_TMP_DIR/reinject.out"
exec 5>"$E14_16_TMP_DIR/reinject.in"
exec 6<"$E14_16_TMP_DIR/reinject.out"

if ! IFS= read -r -t "$STARTUP_TIMEOUT_SECONDS" reinject_startup <&6; then
  log "FAIL: re-injection client never printed its startup identity line"
  exit 1
fi

echo "PAIR $QR_URI" >&5
if ! IFS= read -r -t "$STARTUP_TIMEOUT_SECONDS" reinject_started <&6; then
  log "FAIL: re-injected PAIR never responded"
  exit 1
fi
if [ "$reinject_started" != "OK PAIRING_STARTED" ]; then
  log "FAIL: re-injected PAIR did not even start: $reinject_started"
  exit 1
fi

REINJECT_OUTCOME=""
reinject_deadline=$((SECONDS + PAIR_TIMEOUT_SECONDS))
while (( SECONDS < reinject_deadline )) && [ -z "$REINJECT_OUTCOME" ]; do
  remaining=$((reinject_deadline - SECONDS))
  [ "$remaining" -lt 1 ] && remaining=1
  if ! IFS= read -r -t "$remaining" line <&6; then
    break
  fi
  case "$line" in
    "EVENT Rejected("*|"EVENT Failed("*)
      REINJECT_OUTCOME="$line"
      ;;
    "EVENT Paired")
      log "FAIL: re-injected QR payload was accepted a second time"
      exit 1
      ;;
    *)
      log "reinject-client: $line"
      ;;
  esac
done
if [ -z "$REINJECT_OUTCOME" ]; then
  log "FAIL: re-injected QR payload produced no Rejected/Failed outcome within ${PAIR_TIMEOUT_SECONDS}s"
  exit 1
fi
log "OK: re-injecting the same QR payload was rejected ($REINJECT_OUTCOME)"

echo "EXIT" >&5 2>/dev/null || true
exec 5>&-
exec 6<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID="$FIRST_CLIENT_PID"

# --- Step 3: kill and relaunch both apps -- the JVM client keeps its identity file/trust --------

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

log "relaunching Mac app (plain -- no pairing window) against the same keychain"
harness_launch "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up after restart"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
fi

start_client "$CLIENT_IDENTITY" "$E14_16_TMP_DIR/client2.in" "$E14_16_TMP_DIR/client2.out"
exec 3>"$E14_16_TMP_DIR/client2.in"
exec 4<"$E14_16_TMP_DIR/client2.out"

client2_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: relaunched JVM client never printed its startup identity line"
  exit 1
}
if [ "$client2_startup" != "$client_startup" ]; then
  log "FAIL: relaunched JVM client identity changed ($client2_startup != $client_startup)"
  exit 1
fi
log "OK: JVM client identity persisted across restart"

# --- Step 4: assert the reconnect reaches Ready with no QR --------------------------------------

FAILED=0
RECONNECT_START=$(date +%s)
echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")"; then
  RECONNECT_ELAPSED=$(( $(date +%s) - RECONNECT_START ))
  if [ "$response" != "OK CONNECTED" ]; then
    log "FAIL: reconnect expected OK CONNECTED, got: $response"
    FAILED=1
  else
    log "OK: reconnect reached Ready using only the persisted trust store (${RECONNECT_ELAPSED}s)"
    # yaml acceptance "reconnect < 10 s" (UC-03 proxy timing, same bound the harness applies to the
    # initial QR-to-Paired pairing time).
    if [ "$RECONNECT_ELAPSED" -ge 10 ]; then
      log "FAIL: reconnect took ${RECONNECT_ELAPSED}s, expected < 10s"
      FAILED=1
    fi
  fi
else
  log "FAIL: reconnect -- no response within ${CONNECT_TIMEOUT_SECONDS}s"
  FAILED=1
fi

if grep -q 'harness-pairing-qr-uri:' "$HARNESS_LOG_PATH"; then
  log "FAIL: the relaunched Mac app printed a pairing QR URI -- it should never have opened one"
  FAILED=1
else
  log "OK: no QR involved in the reconnect"
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-

if [ "$FAILED" -ne 0 ]; then
  log "e14-16 integration FAILED"
  exit 1
fi
log "e14-16 integration OK"
exit 0
