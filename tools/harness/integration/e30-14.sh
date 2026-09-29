#!/usr/bin/env bash
# E30-14: notification-latency loopback (notificationLatencyLoopback_twoHundredFrames_p95PresenterCallUnder100ms).
#
# One E15-15 JVM harness client sends 200 `NotificationPosted` frames on NOTIFY to the real Mac app
# (`tools/harness/mac-driver.sh`), launched with the new DEBUG `-HarnessNotificationLoopback YES`
# hook (`TandemApp/HarnessHooks.swift`'s `HarnessNotificationLoopbackSessionRegistry`, wrapping a
# DEBUG-only `HarnessLatencyNotificationPresenter`). Each frame's notification text carries only its
# own decimal sequence number (`HarnessCli.sendNotifications`) -- never real content (invariant 7).
#
# The client prints `EVENT SENT <sequence> <epochMillis>` immediately before each send; the Mac logs
# `harness-notification-latency: <sequence> <epochMillis>` from the presenter's own `add(_:)` call.
# Both are epoch milliseconds off the same machine's clock (this is a loopback test: no cross-device
# clock offset applies, unlike the two-Wi-Fi-device manual gate this issue also describes), so this
# script joins the two logs by sequence number, computes each frame's latency directly, and hands
# the resulting `<sequence> <latencyMillis>` pairs to the *same* nearest-rank p95 pure function this
# issue's unit tests cover (`dev.tandem.harness.jvmclient.latency.NearestRankPercentile`, invoked via
# `LatencyReportCli`) -- never a second, divergent percentile calculation.
#
# The report this script writes (and the log lines both processes print) contains only sequence
# numbers and timings -- never notification content (invariant 7's own `latencyReportWriter` tdd).
set -uo pipefail

E30_14_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E30_14_ROOT/android"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
LATENCY_REPORT_MAIN_CLASS="dev.tandem.harness.jvmclient.latency.LatencyReportCliKt"
STARTUP_TIMEOUT_SECONDS=10
CONNECT_TIMEOUT_SECONDS=5
NOTIFICATION_COUNT=200
SEND_TIMEOUT_SECONDS=30
DRAIN_TIMEOUT_SECONDS=15
P95_BUDGET_MS=100

# shellcheck source=../mac-driver.sh
source "$E30_14_ROOT/tools/harness/mac-driver.sh"

E30_14_TMP_DIR=""
E30_14_CLASSPATH=""
CLIENT_PID=""
FAILED=0

log() { echo "e30-14: $*" >&2; }

cleanup() {
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    kill "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
  fi
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  harness_cleanup
  if [ -n "$E30_14_TMP_DIR" ] && [ -d "$E30_14_TMP_DIR" ]; then
    if [ "${FAILED:-0}" -ne 0 ]; then
      for stderr_log in "$E30_14_TMP_DIR"/*.stderr.log; do
        [ -s "$stderr_log" ] && { log "--- $stderr_log ---"; cat "$stderr_log" >&2; }
      done
    fi
    rm -rf "$E30_14_TMP_DIR"
  fi
}
trap cleanup EXIT

if [ "$(uname)" != "Darwin" ]; then
  log "FAIL: this integration test requires the real macOS NWListener server -- not skipping"
  exit 1
fi

hex_to_base64url() {
  xxd -r -p | base64 | tr '+/' '-_' | tr -d '=\n'
}

write_seed_fixture() {
  local fingerprint_hex="$1"
  local out_path="$2"
  cat > "$out_path" <<JSON
{
  "fingerprintHex": "$fingerprint_hex",
  "displayName": "e30-14 jvm harness client",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
}

start_client() {
  local identity_file="$1"
  local in_fifo="$2"
  local out_fifo="$3"
  mkfifo "$in_fifo" "$out_fifo"
  "$JAVA_BIN" --enable-native-access=ALL-UNNAMED -cp "$E30_14_CLASSPATH" "$JVM_MAIN_CLASS" \
    --identity-file "$identity_file" \
    <"$in_fifo" >"$out_fifo" 2>"$identity_file.stderr.log" &
  CLIENT_PID=$!
}

read_response() {
  local timeout_seconds="$1"
  local line
  if IFS= read -r -t "$timeout_seconds" line <&4; then
    printf '%s\n' "$line"
    return 0
  fi
  return 1
}

log "resolving JVM harness client runtime classpath (build once)"
if ! E30_14_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not build/resolve the jvm-client runtime classpath"
  exit 1
fi
E30_14_CLASSPATH="${E30_14_CLASSPATH%:}"

E30_14_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e30-14.XXXXXX")"
CLIENT_IDENTITY="$E30_14_TMP_DIR/client-identity.bin"

log "building and launching the real Mac app with -HarnessNotificationLoopback YES (build once)"
if ! harness_init; then
  log "FAIL: Mac app build failed"
  exit 1
fi

MAC_PORT=$(( (RANDOM % 20000) + 20000 ))
harness_launch "$MAC_PORT" -HarnessNotificationLoopback YES
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came up on port $MAC_PORT"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
fi
log "OK: Mac listener up on port $MAC_PORT"

MAC_SPKI="$(harness_identity_spki)"
if [ -z "$MAC_SPKI" ]; then
  log "FAIL: no harness-identity-spki line from the Mac app"
  exit 1
fi
MAC_FP_B64="$(printf '%s' "$MAC_SPKI" | hex_to_base64url)"

start_client "$CLIENT_IDENTITY" "$E30_14_TMP_DIR/client.in" "$E30_14_TMP_DIR/client.out"
exec 3>"$E30_14_TMP_DIR/client.in"
exec 4<"$E30_14_TMP_DIR/client.out"

client_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: JVM client never printed its startup identity line"
  FAILED=1
}
CLIENT_SPKI=""
case "$client_startup" in
  "harness-identity-spki: "*) CLIENT_SPKI="${client_startup#harness-identity-spki: }" ;;
  *) log "FAIL: JVM client unexpected startup line: $client_startup"; FAILED=1 ;;
esac

if [ "$FAILED" -eq 0 ]; then
  # Seeding writes to the on-disk file keychain the running listener has open; stop the listener
  # first (e15-15.sh's own ordering), seed, then relaunch the identical, un-rebuilt binary.
  harness_kill
  seed_fixture_path="$E30_14_TMP_DIR/seed-client.json"
  write_seed_fixture "$CLIENT_SPKI" "$seed_fixture_path"
  if ! harness_seed_trust "$seed_fixture_path"; then
    log "FAIL: -HarnessSeedTrust failed"
    FAILED=1
  fi
  harness_launch "$MAC_PORT" -HarnessNotificationLoopback YES
  if ! harness_wait_for_listening "$MAC_PORT"; then
    log "FAIL: Mac listener never came back up after seeding trust"
    cat "$HARNESS_LOG_PATH" >&2
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")"; then
    if [ "$response" != "OK CONNECTED" ]; then
      log "FAIL: expected \"OK CONNECTED\", got: $response"
      FAILED=1
    fi
  else
    log "FAIL: no CONNECT response within ${CONNECT_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
fi

CLIENT_SENT_LOG="$E30_14_TMP_DIR/client-sent.log"
if [ "$FAILED" -eq 0 ]; then
  log "OK: connected, sending $NOTIFICATION_COUNT NotificationPosted frames"
  echo "SENDNOTIFICATIONS $NOTIFICATION_COUNT" >&3
  : > "$CLIENT_SENT_LOG"
  sent_count=0
  while [ "$sent_count" -lt "$NOTIFICATION_COUNT" ]; do
    if ! response="$(read_response "$SEND_TIMEOUT_SECONDS")"; then
      log "FAIL: timed out waiting for EVENT SENT lines ($sent_count/$NOTIFICATION_COUNT so far)"
      FAILED=1
      break
    fi
    case "$response" in
      "EVENT SENT "*)
        echo "${response#EVENT SENT }" >> "$CLIENT_SENT_LOG"
        sent_count=$((sent_count + 1))
        ;;
      *)
        log "FAIL: unexpected line while sending: $response"
        FAILED=1
        break
        ;;
    esac
  done
  if [ "$FAILED" -eq 0 ]; then
    if ! response="$(read_response "$SEND_TIMEOUT_SECONDS")" || [ "$response" != "OK SENT_ALL $NOTIFICATION_COUNT" ]; then
      log "FAIL: expected \"OK SENT_ALL $NOTIFICATION_COUNT\", got: ${response:-<no response>}"
      FAILED=1
    fi
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  log "OK: sent $NOTIFICATION_COUNT frames, waiting for the Mac to present all of them"
  waited=0
  while [ "$waited" -lt "$DRAIN_TIMEOUT_SECONDS" ]; do
    presented_count="$(grep -c '^harness-notification-latency: ' "$HARNESS_LOG_PATH" || true)"
    if [ "$presented_count" -ge "$NOTIFICATION_COUNT" ]; then
      break
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  presented_count="$(grep -c '^harness-notification-latency: ' "$HARNESS_LOG_PATH" || true)"
  if [ "$presented_count" -lt "$NOTIFICATION_COUNT" ]; then
    log "FAIL: only $presented_count/$NOTIFICATION_COUNT notifications presented within ${DRAIN_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  # Joins the client's own "<sequence> <sentEpochMillis>" lines against the Mac's
  # "harness-notification-latency: <sequence> <addEpochMillis>" lines by sequence number, computing
  # each frame's latency (add time minus send time -- same-machine clock, no offset needed).
  samples_path="$E30_14_TMP_DIR/samples.txt"
  sed -n 's/^harness-notification-latency: //p' "$HARNESS_LOG_PATH" | sort -n > "$E30_14_TMP_DIR/presented.log"
  sort -n "$CLIENT_SENT_LOG" -o "$CLIENT_SENT_LOG"
  join -j 1 "$CLIENT_SENT_LOG" "$E30_14_TMP_DIR/presented.log" \
    | awk '{print $1, $3 - $2}' > "$samples_path"
  sample_count="$(wc -l < "$samples_path" | tr -d ' ')"
  if [ "$sample_count" -ne "$NOTIFICATION_COUNT" ]; then
    log "FAIL: joined $sample_count samples, expected $NOTIFICATION_COUNT"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  report_path="$E30_14_TMP_DIR/report.txt"
  if ! "$JAVA_BIN" -cp "$E30_14_CLASSPATH" "$LATENCY_REPORT_MAIN_CLASS" "$samples_path" > "$report_path"; then
    log "FAIL: LatencyReportCli failed"
    FAILED=1
  else
    p95_ms="$(sed -n 's/^p95_ms //p' "$report_path")"
    log "report:"
    cat "$report_path" >&2
    if [ -z "$p95_ms" ]; then
      log "FAIL: report had no p95_ms line"
      FAILED=1
    elif [ "$p95_ms" -ge "$P95_BUDGET_MS" ]; then
      log "FAIL: notificationLatencyLoopback_twoHundredFrames_p95PresenterCallUnder100ms -- p95 ${p95_ms}ms >= ${P95_BUDGET_MS}ms"
      FAILED=1
    else
      log "OK: notificationLatencyLoopback_twoHundredFrames_p95PresenterCallUnder100ms -- p95 ${p95_ms}ms < ${P95_BUDGET_MS}ms"
    fi
  fi
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

if [ "$FAILED" -ne 0 ]; then
  log "e30-14 integration FAILED"
  exit 1
fi
log "e30-14 integration OK"
exit 0
