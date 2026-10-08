#!/usr/bin/env bash
# E23-08: status throttle and ring round-trip tests, on the E15-15/E12-13 harness join -- the real
# Mac app under `tools/harness/mac-driver.sh` (D-75 file keychain, never the login keychain, never
# signed, built once) and the real JVM harness client CLI (`android/harness/jvm-client`, built
# once), talking real mTLS on 127.0.0.1 only. Runs the four `integration:` scenarios this issue's
# `tdd:` list assigns to this harness (the fifth entry, `manual: findPhoneFromMacMenu_...`, needs a
# physical phone in silent+DND and is out of scope here, per docs/testing/manual-gates.md):
#
#   1. statusBurst20ChangesIn5s_macServer_atMostTwoFramesIn65s -- the JVM client pushes 20 distinct
#      `DeviceStatus` values into the real `StatusPublisher` (E23-03, `feature:status`, linked onto
#      this harness's JVM classpath exactly like `core/*`) over ~5s; the Mac's real STATUS-channel
#      reader (`HarnessRevokeAwareSessionRegistry`'s `-HarnessStreamStatus YES` tap) must see at
#      most 2 `DeviceStatus` frames in the 65s following the first push (leading + one trailing).
#   2. ringRoundTrip_ringStopFromMac_phoneAlarmStoppedWithin1s -- the Mac's real `FindPhoneViewModel`
#      (E23-07, driven via `-HarnessInteractiveCommands YES`'s `FINDPHONE` command) sends a `Ring`,
#      then a `RingStop{origin: mac}`; the JVM client's `HarnessRingReactor` (a harness-local
#      stand-in for `RingController`'s alarm-start/stop counting -- see that class's own kdoc for
#      why it isn't the real class) must stop within 1s of the `RingStop`.
#   3. statusChangeOutsideThrottleWindow_macViewModel_updatedWithin2s -- a status change sent more
#      than 60s (the real E23-03 throttle window) after the last one must reach the Mac within 2s.
#   4. ringFlood_macSends20RingsIn5s_phoneAlarmStartedAtMostTwice -- 20 raw `Ring` frames
#      (`SENDRAWRING`, bypassing `FindPhoneViewModel`'s idle/ringing toggle, which cannot produce
#      20 `Ring`s without an intervening `RingStop`) in 5s must start the JVM client's alarm
#      reactor at most twice (D-62's cooldown, mirrored by `HarnessRingReactor`).
#
# All four scenarios reuse one real mTLS session, connected once near the top of the script and
# torn down at the end -- status throttle, ring round trip and ring flood are independent
# behaviors of the same live connection, not separate connections to set up per scenario.
set -uo pipefail

E23_08_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E23_08_ROOT/android"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
STARTUP_TIMEOUT_SECONDS=10
CONNECT_TIMEOUT_SECONDS=5
COMMAND_TIMEOUT_SECONDS=5
THROTTLE_WINDOW_SECONDS=60
BURST_WAIT_SECONDS=65
# A margin over BURST_WAIT_SECONDS/STATUS_ASSERT_MS/RING_ASSERT_MS: this script's own IPC/fifo
# plumbing and coroutine scheduling can lag the acceptance numbers below under host load without
# that being a real production-code delay, so each WAIT constant is a generous upper bound the
# poll loop gives up at, while PASS/FAIL is still judged strictly against the ASSERT constant
# using the real measured elapsed time -- a slow, honestly-reported failure, never a silently
# widened acceptance bound.
BURST_WAIT_MARGIN_SECONDS=15
OUTSIDE_WINDOW_WAIT_SECONDS=$((THROTTLE_WINDOW_SECONDS + 1))
RING_ASSERT_MS=1000
RING_WAIT_MS=8000
STATUS_ASSERT_MS=2000
STATUS_WAIT_MS=8000
POLL_INTERVAL_SECONDS=0.1

# shellcheck source=../mac-driver.sh
source "$E23_08_ROOT/tools/harness/mac-driver.sh"
# shellcheck source=../scenario-watchdog.sh
SCENARIO_LOG_PREFIX="e23-08"
source "$E23_08_ROOT/tools/harness/scenario-watchdog.sh"

# Hard per-scenario deadlines (E23-09): each is the scenario's own worst-case wall time (every
# internal wait at its upper bound) plus slack, so a stuck read/write aborts the script instead of
# hanging it.
SCENARIO_1_DEADLINE_SECONDS=200
SCENARIO_3_DEADLINE_SECONDS=150
SCENARIO_2_DEADLINE_SECONDS=60
SCENARIO_4_DEADLINE_SECONDS=90

E23_08_TMP_DIR=""
E23_08_CLASSPATH=""
CLIENT_PID=""
MAC_STDIN_FIFO=""

log() { echo "e23-08: $*" >&2; }

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

cleanup() {
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    kill "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
  fi
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  exec 6>&- 2>/dev/null || true
  harness_cleanup
  if [ -n "$E23_08_TMP_DIR" ] && [ -d "$E23_08_TMP_DIR" ]; then
    rm -rf "$E23_08_TMP_DIR"
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
  "displayName": "e23-08 jvm harness client",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
}

# Launches the real Mac app with its STATUS-channel tap and interactive Ring/RingStop command loop
# on ($1)'s stdin -- a fifo, wired via fd 6, mirroring `start_client`'s own fifo dance below (open
# the read side as part of launching the background process, then open the write side from this
# script to unblock it, exactly as `tools/harness/integration/e15-15.sh`'s `start_client` does for
# the JVM client's stdin). Not part of `mac-driver.sh` itself: no other script needs a live stdin
# into the Mac app.
launch_mac_interactive() {
  local port="$1"
  MAC_STDIN_FIFO="$HARNESS_TMP_DIR/mac-stdin.fifo"
  rm -f "$MAC_STDIN_FIFO"
  mkfifo "$MAC_STDIN_FIFO"
  : > "$HARNESS_LOG_PATH"
  TANDEM_HARNESS_KEYCHAIN_PASSWORD="$HARNESS_KEYCHAIN_PASSWORD" \
    "$HARNESS_APP_BINARY" \
    -HarnessKeychainPath "$HARNESS_KEYCHAIN_PATH" \
    -HarnessListenerPort "$port" \
    -HarnessInteractiveCommands YES \
    -HarnessStreamStatus YES \
    <"$MAC_STDIN_FIFO" >>"$HARNESS_LOG_PATH" 2>&1 &
  HARNESS_PID=$!
  exec 6>"$MAC_STDIN_FIFO"
  harness_log "launched interactive pid $HARNESS_PID on port $port"
}

mac_command() {
  printf '%s\n' "$1" >&6
}

start_client() {
  local identity_file="$1"
  local in_fifo="$2"
  local out_fifo="$3"
  mkfifo "$in_fifo" "$out_fifo"
  # `--enable-native-access=ALL-UNNAMED`/`--sun-misc-unsafe-memory-access=allow`: JDK 24+ prints
  # `WARNING:` lines to stderr (merged into this fifo below) the moment Conscrypt's native library
  # loads and the first time protobuf's `UnsafeUtil` touches `sun.misc.Unsafe` -- unpredictably
  # interleaved with this process's own protocol lines on this JDK, not something every read in
  # this script should have to filter around. A pre-existing environmental wrinkle, not anything
  # E23-08 introduces.
  "$JAVA_BIN" --enable-native-access=ALL-UNNAMED --sun-misc-unsafe-memory-access=allow \
    -cp "$E23_08_CLASSPATH" "$JVM_MAIN_CLASS" --identity-file "$identity_file" \
    <"$in_fifo" >"$out_fifo" 2>&1 &
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

# Reads lines from fd 4 until one starts with $1 or $2 (whichever comes first) elapses, logging
# anything else; prints elapsed milliseconds and the matching line, space-separated, on success.
wait_for_client_prefix_ms() {
  local prefix="$1"
  local timeout_ms="$2"
  local start_ms
  start_ms="$(now_ms)"
  # Bounds the loop by iteration count (timeout_ms / POLL_INTERVAL_SECONDS), not by re-querying
  # wall time every iteration: this line is read up to ~80 times for an 8s timeout, and spawning a
  # fresh `python3` subprocess on every single one of those (the original, simpler shape) is both
  # wasteful and -- reproduced directly -- can itself perturb the fifo read enough to lose the very
  # line this function is waiting for. `now_ms` is only called once more, on an actual match.
  local max_iterations=$(( (timeout_ms * 10 / 1000) + 1 ))
  local line
  local iteration=0
  while [ "$iteration" -lt "$max_iterations" ]; do
    iteration=$((iteration + 1))
    if IFS= read -r -t "$POLL_INTERVAL_SECONDS" line <&4; then
      case "$line" in
        "$prefix"*)
          printf '%s %s\n' "$(( $(now_ms) - start_ms ))" "$line"
          return 0
          ;;
        *)
          log "jvm-client: $line"
          ;;
      esac
    fi
  done
  return 1
}

# Polls the Mac log for a NEW `harness-status-received:` line (one not already among the first
# $1 such lines) until $2 ms elapse; prints elapsed milliseconds and the new line on success.
wait_for_new_status_line_ms() {
  local already_seen_count="$1"
  local timeout_ms="$2"
  local start_ms
  start_ms="$(now_ms)"
  local max_iterations=$(( (timeout_ms * 10 / 1000) + 1 ))
  local iteration=0
  while [ "$iteration" -lt "$max_iterations" ]; do
    iteration=$((iteration + 1))
    local current_count
    current_count="$(grep -c '^harness-status-received: ' "$HARNESS_LOG_PATH" 2>/dev/null || true)"
    if [ "$current_count" -gt "$already_seen_count" ]; then
      printf '%s %s\n' "$(( $(now_ms) - start_ms ))" "$(grep '^harness-status-received: ' "$HARNESS_LOG_PATH" | tail -1)"
      return 0
    fi
    sleep "$POLL_INTERVAL_SECONDS"
  done
  return 1
}

FAILED=0

log "resolving JVM harness client runtime classpath (build once)"
if ! E23_08_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not build/resolve the jvm-client runtime classpath"
  exit 1
fi
E23_08_CLASSPATH="${E23_08_CLASSPATH%:}"

E23_08_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e23-08.XXXXXX")"
CLIENT_IDENTITY="$E23_08_TMP_DIR/client-identity.bin"

log "building the real Mac app (build once)"
if ! harness_init; then
  log "FAIL: Mac app build failed"
  exit 1
fi

MAC_PORT=$(( (RANDOM % 20000) + 20000 ))

# --- Setup: connect one real mTLS session, reused by every scenario below ------------------------

log "launching Mac app (interactive + status streaming)"
launch_mac_interactive "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came up on port $MAC_PORT"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
fi
MAC_SPKI_HEX="$(harness_identity_spki)"
if [ -z "$MAC_SPKI_HEX" ]; then
  log "FAIL: no harness-identity-spki line from the Mac app"
  exit 1
fi
MAC_FP_B64="$(printf '%s' "$MAC_SPKI_HEX" | hex_to_base64url)"

start_client "$CLIENT_IDENTITY" "$E23_08_TMP_DIR/client.in" "$E23_08_TMP_DIR/client.out"
exec 3>"$E23_08_TMP_DIR/client.in"
exec 4<"$E23_08_TMP_DIR/client.out"

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
CLIENT_FP_HEX="${client_startup#harness-identity-spki: }"

log "seeding the JVM client's identity into the Mac trust store"
echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
wait "$CLIENT_PID" 2>/dev/null
CLIENT_PID=""
exec 6>&-
harness_kill

SEED_FIXTURE_PATH="$E23_08_TMP_DIR/seed-client.json"
write_seed_fixture "$CLIENT_FP_HEX" "$SEED_FIXTURE_PATH"
if ! harness_seed_trust "$SEED_FIXTURE_PATH"; then
  log "FAIL: -HarnessSeedTrust failed"
  exit 1
fi
launch_mac_interactive "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up after seeding trust"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
fi

start_client "$CLIENT_IDENTITY" "$E23_08_TMP_DIR/client2.in" "$E23_08_TMP_DIR/client2.out"
exec 3>"$E23_08_TMP_DIR/client2.in"
exec 4<"$E23_08_TMP_DIR/client2.out"
client_startup2="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: relaunched JVM client never printed its startup identity line"
  exit 1
}
if [ "$client_startup2" != "$client_startup" ]; then
  log "FAIL: relaunched JVM client identity changed ($client_startup2 != $client_startup)"
  exit 1
fi

echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")" && [ "$response" = "OK CONNECTED" ]; then
  log "OK: real mTLS session Ready (seeded trust, single identity reused by every scenario below)"
else
  log "FAIL: CONNECT never reached OK CONNECTED, got: ${response:-<timeout>}"
  exit 1
fi

# --- Scenario 1: statusBurst20ChangesIn5s_macServer_atMostTwoFramesIn65s -------------------------

scenario_begin "1 statusBurst" "$SCENARIO_1_DEADLINE_SECONDS"
BEFORE_BURST_STATUS_COUNT="$(grep -c '^harness-status-received: ' "$HARNESS_LOG_PATH" 2>/dev/null || true)"
BURST_START_MS="$(now_ms)"
for i in $(seq 1 20); do
  battery=$(( (i % 100) + 1 ))
  echo "STATUS $battery 0 WIFI 3" >&3
  read_response "$COMMAND_TIMEOUT_SECONDS" >/dev/null || true
  sleep 0.25
done
BURST_SEND_ELAPSED_MS=$(( $(now_ms) - BURST_START_MS ))
log "sent 20 distinct DeviceStatus changes to the JVM client's real StatusPublisher over ${BURST_SEND_ELAPSED_MS}ms"

REMAINING_WAIT_SECONDS=$(( BURST_WAIT_SECONDS + BURST_WAIT_MARGIN_SECONDS - (BURST_SEND_ELAPSED_MS / 1000) ))
[ "$REMAINING_WAIT_SECONDS" -lt 1 ] && REMAINING_WAIT_SECONDS=1
log "waiting ${REMAINING_WAIT_SECONDS}s more (total ~$((BURST_WAIT_SECONDS + BURST_WAIT_MARGIN_SECONDS))s since the first change, ${BURST_WAIT_SECONDS}s acceptance + ${BURST_WAIT_MARGIN_SECONDS}s harness-plumbing margin) for the Mac to observe leading+trailing sends"
sleep "$REMAINING_WAIT_SECONDS"

AFTER_BURST_STATUS_COUNT="$(grep -c '^harness-status-received: ' "$HARNESS_LOG_PATH" 2>/dev/null || true)"
BURST_FRAME_COUNT=$((AFTER_BURST_STATUS_COUNT - BEFORE_BURST_STATUS_COUNT))
log "measured: $BURST_FRAME_COUNT DeviceStatus frame(s) reached the Mac (raw log lines: $(grep '^harness-status-received: ' "$HARNESS_LOG_PATH" | tail -"$BURST_FRAME_COUNT" | tr '\n' ';'))"
if [ "$BURST_FRAME_COUNT" -ge 1 ] && [ "$BURST_FRAME_COUNT" -le 2 ]; then
  log "OK: statusBurst20ChangesIn5s_macServer_atMostTwoFramesIn65s ($BURST_FRAME_COUNT frame(s))"
else
  log "FAIL: statusBurst20ChangesIn5s_macServer_atMostTwoFramesIn65s -- expected 1-2 frames, got $BURST_FRAME_COUNT"
  FAILED=1
fi

scenario_end

# --- Scenario 3: statusChangeOutsideThrottleWindow_macViewModel_updatedWithin2s ------------------
# The real throttle window (StatusPublisher, E23-03) is measured from the last *actual send*, not
# from scenario 1's own burst start -- scenario 1's trailing send fires ~60s after its leading one
# (i.e. around now, not at burst start), so this scenario must wait until >60s have passed since
# that LAST OBSERVED frame's own printed epoch millis, or its own change would just coalesce into
# a second throttled send rather than landing outside the window at all.

scenario_begin "3 statusOutsideWindow" "$SCENARIO_3_DEADLINE_SECONDS"
LAST_BURST_STATUS_EPOCH_MS="$(grep -o '^harness-status-received: [0-9]*' "$HARNESS_LOG_PATH" | tail -1 | awk '{print $2}')"
if [ -n "$LAST_BURST_STATUS_EPOCH_MS" ]; then
  SINCE_LAST_SEND_MS=$(( $(now_ms) - LAST_BURST_STATUS_EPOCH_MS ))
  EXTRA_WAIT_MS=$(( (THROTTLE_WINDOW_SECONDS * 1000) + 2000 - SINCE_LAST_SEND_MS ))
  if [ "$EXTRA_WAIT_MS" -gt 0 ]; then
    log "waiting ${EXTRA_WAIT_MS}ms more so >${THROTTLE_WINDOW_SECONDS}s have passed since the last real send ($LAST_BURST_STATUS_EPOCH_MS) before scenario 3's own change"
    sleep "$(python3 -c "print($EXTRA_WAIT_MS / 1000)")"
  fi
fi

BEFORE_OUTSIDE_STATUS_COUNT="$(grep -c '^harness-status-received: ' "$HARNESS_LOG_PATH" 2>/dev/null || true)"
OUTSIDE_SEND_MS="$(now_ms)"
echo "STATUS 77 1 CELLULAR 2" >&3
read_response "$COMMAND_TIMEOUT_SECONDS" >/dev/null || true

if result="$(wait_for_new_status_line_ms "$BEFORE_OUTSIDE_STATUS_COUNT" "$STATUS_WAIT_MS")"; then
  elapsed_ms="${result%% *}"
  line="${result#* }"
  log "measured: Mac observed the out-of-window status change in ${elapsed_ms}ms ($line)"
  if [ "$elapsed_ms" -le "$STATUS_ASSERT_MS" ]; then
    log "OK: statusChangeOutsideThrottleWindow_macViewModel_updatedWithin2s (${elapsed_ms}ms)"
  else
    log "FAIL: statusChangeOutsideThrottleWindow_macViewModel_updatedWithin2s -- ${elapsed_ms}ms > ${STATUS_ASSERT_MS}ms"
    FAILED=1
  fi
else
  log "FAIL: statusChangeOutsideThrottleWindow_macViewModel_updatedWithin2s -- no new frame within ${STATUS_ASSERT_MS}ms"
  FAILED=1
fi
unset OUTSIDE_SEND_MS
scenario_end

# --- Scenario 2: ringRoundTrip_ringStopFromMac_phoneAlarmStoppedWithin1s -------------------------

scenario_begin "2 ringRoundTrip" "$SCENARIO_2_DEADLINE_SECONDS"
log "Mac (real FindPhoneViewModel) selecting Find Phone -- sends Ring"
mac_command "FINDPHONE $CLIENT_FP_HEX"
if result="$(wait_for_client_prefix_ms "EVENT RING_STARTED" "$RING_WAIT_MS")"; then
  elapsed_ms="${result%% *}"
  log "measured: JVM client's alarm reactor started in ${elapsed_ms}ms (${result#* })"
else
  log "FAIL: ringRoundTrip -- JVM client never reported EVENT RING_STARTED"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

log "Mac (real FindPhoneViewModel) selecting Stop Ringing -- sends RingStop{origin: mac}"
mac_command "FINDPHONE $CLIENT_FP_HEX"
if result="$(wait_for_client_prefix_ms "EVENT RING_STOPPED" "$RING_WAIT_MS")"; then
  elapsed_ms="${result%% *}"
  log "measured: JVM client's alarm reactor stopped in ${elapsed_ms}ms (${result#* })"
  if [ "$elapsed_ms" -le "$RING_ASSERT_MS" ]; then
    log "OK: ringRoundTrip_ringStopFromMac_phoneAlarmStoppedWithin1s (${elapsed_ms}ms)"
  else
    log "FAIL: ringRoundTrip_ringStopFromMac_phoneAlarmStoppedWithin1s -- ${elapsed_ms}ms > ${RING_ASSERT_MS}ms"
    FAILED=1
  fi
else
  log "FAIL: ringRoundTrip_ringStopFromMac_phoneAlarmStoppedWithin1s -- no EVENT RING_STOPPED within ${RING_ASSERT_MS}ms"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

scenario_end

# --- Scenario 4: ringFlood_macSends20RingsIn5s_phoneAlarmStartedAtMostTwice ----------------------
# D-62's cooldown is a rolling 10s window; wait past it first so this scenario starts from a clean
# "not currently ringing, no recent starts" state regardless of scenario 2's own start/stop above.
scenario_begin "4 ringFlood" "$SCENARIO_4_DEADLINE_SECONDS"
log "waiting 11s past D-62's rolling cooldown window before the flood"
sleep 11

FLOOD_INTERVAL_MS=263 # 19 gaps over ~5000ms for 20 sends
FLOOD_COUNT=20
# `SENDRAWRING`'s own "OK SENT_RAW_RINGS" ack goes to the Mac process's stdout (the harness log
# file), not this client's fifo -- there is nothing to read from fd 4 here, so this just waits out
# the flood's own expected wall time (19 gaps of FLOOD_INTERVAL_MS) plus a margin for scheduling
# jitter and the client's own processing of the last few frames.
log "Mac sending $FLOOD_COUNT raw Ring frames over ~5s (bypassing FindPhoneViewModel's idle/ringing toggle)"
FLOOD_START_MS="$(now_ms)"
mac_command "SENDRAWRING $CLIENT_FP_HEX $FLOOD_COUNT $FLOOD_INTERVAL_MS"
FLOOD_EXPECTED_MS=$(( (FLOOD_COUNT - 1) * FLOOD_INTERVAL_MS + 2000 ))
sleep "$(python3 -c "print($FLOOD_EXPECTED_MS / 1000)")"
FLOOD_SEND_ELAPSED_MS=$(( $(now_ms) - FLOOD_START_MS ))
log "waited ${FLOOD_SEND_ELAPSED_MS}ms for the Mac to finish sending the flood"

echo "RINGSTATE" >&3
ringstate_response=""
if result="$(wait_for_client_prefix_ms "OK RINGING=" "$((COMMAND_TIMEOUT_SECONDS * 1000))")"; then
  ringstate_response="${result#* }"
else
  log "FAIL: ringFlood -- RINGSTATE never responded"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi
log "measured: JVM client reactor state after the flood: $ringstate_response"
STARTS="$(printf '%s' "$ringstate_response" | sed -n 's/.*STARTS=\([0-9]*\).*/\1/p')"
if [ -n "$STARTS" ] && [ "$STARTS" -ge 1 ] && [ "$STARTS" -le 2 ]; then
  log "OK: ringFlood_macSends20RingsIn5s_phoneAlarmStartedAtMostTwice (startCount=$STARTS)"
else
  log "FAIL: ringFlood_macSends20RingsIn5s_phoneAlarmStartedAtMostTwice -- expected STARTS 1-2, got: $ringstate_response"
  FAILED=1
fi

scenario_end

# --- Teardown -------------------------------------------------------------------------------------

echo "DISCONNECT" >&3 2>/dev/null || true
read_response "$COMMAND_TIMEOUT_SECONDS" >/dev/null || true
echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

if [ "$FAILED" -ne 0 ]; then
  log "e23-08 integration FAILED"
  exit 1
fi
log "e23-08 integration OK"
exit 0
