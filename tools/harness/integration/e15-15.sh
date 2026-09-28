#!/usr/bin/env bash
# E15-15: the join issue's own end-to-end proof -- one JVM harness client (E15-21) against the
# real Mac server app (E15-22, `tools/harness/mac-driver.sh`, D-75 file keychain, never the login
# keychain, never signed, built once) exercising the four acceptance criteria in the order the
# issue states them, all against the *same* client identity so each step actually proves what it
# claims about that one identity rather than about the harness in general:
#
#   1. jvmHarness_seededTrustRecord_clientCompletesHandshake -- seed the client's identity into
#      the Mac trust store, then a pinned CONNECT reaches `OK CONNECTED` (mTLS handshake plus the
#      VersionHello exchange, see core/protocol/connection/ConnectionState.kt).
#   2. jvmHarness_restartBothProcesses_sameIdentityAndHandshakeSucceeds -- kill and relaunch both
#      the Mac app (same on-disk keychain, no rebuild) and the JVM client process (same
#      `--identity-file`) unattended; the client's own identity SPKI, the Mac's own identity SPKI
#      and the seeded trust record must all be unchanged, and a fresh CONNECT must still reach
#      `OK CONNECTED`.
#   3. jvmHarness_clearedTrustStore_handshakeRejected -- with that same still-running client,
#      `-HarnessClearTrust` the Mac's trust store; the next CONNECT from the very same identity
#      that worked a moment ago must now be rejected server-side, proving it was the seeded record
#      (not something else) granting access.
#
# Acceptance #4 ("no physical device or emulator, < 15 min wall time") is enforced by the CI job
# that invokes this script (`.github/workflows/macos.yml`, `jvm-harness`), via a hard `timeout`
# around the whole harness step -- not by this script, which has no wall-clock budget of its own
# to enforce.
#
# E12-13 already covers the handshake/Hello/frame-round-trip scenarios (including a *never*-seeded
# client rejected server-side) and E14-16 already covers QR pairing plus restart-both/reconnect;
# neither exercises seed -> success -> restart -> success -> clear -> reject on one identity, which
# is exactly what this issue's acceptance list asks for, so this script is new rather than a thin
# wrapper around either of them.
set -uo pipefail

E15_15_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E15_15_ROOT/android"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
CONNECT_TIMEOUT_SECONDS=5
REJECT_TIMEOUT_SECONDS=15
STARTUP_TIMEOUT_SECONDS=10

# shellcheck source=../mac-driver.sh
source "$E15_15_ROOT/tools/harness/mac-driver.sh"

E15_15_TMP_DIR=""
E15_15_CLASSPATH=""
CLIENT_PID=""

log() { echo "e15-15: $*" >&2; }

cleanup() {
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    kill "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
  fi
  # Best-effort: fds may already be closed by the step that opened them.
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  harness_cleanup
  if [ -n "$E15_15_TMP_DIR" ] && [ -d "$E15_15_TMP_DIR" ]; then
    rm -rf "$E15_15_TMP_DIR"
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

# Writes a `-HarnessSeedTrust` fixture for a peer identified by $1's hex SPKI fingerprint to $2.
write_seed_fixture() {
  local fingerprint_hex="$1"
  local out_path="$2"
  cat > "$out_path" <<JSON
{
  "fingerprintHex": "$fingerprint_hex",
  "displayName": "e15-15 jvm harness client",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
}

# Starts a fresh JVM harness client process with its own identity file, piped through the fifos at
# $2 (stdin) / $3 (stdout+stderr); sets $CLIENT_PID. Does not open either fifo end -- the caller
# does that so it can be re-run against a fresh pair of fifos across a restart.
start_client() {
  local identity_file="$1"
  local in_fifo="$2"
  local out_fifo="$3"
  mkfifo "$in_fifo" "$out_fifo"
  "$JAVA_BIN" -cp "$E15_15_CLASSPATH" "$JVM_MAIN_CLASS" --identity-file "$identity_file" \
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

FAILED=0

log "resolving JVM harness client runtime classpath (build once)"
if ! E15_15_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not build/resolve the jvm-client runtime classpath"
  exit 1
fi
E15_15_CLASSPATH="${E15_15_CLASSPATH%:}"

E15_15_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e15-15.XXXXXX")"
CLIENT_IDENTITY="$E15_15_TMP_DIR/client-identity.bin"

log "building and launching the real Mac app (build once)"
if ! harness_init; then
  log "FAIL: Mac app build failed"
  exit 1
fi

MAC_PORT=$(( (RANDOM % 20000) + 20000 ))
harness_launch "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came up on port $MAC_PORT"
  cat "$HARNESS_LOG_PATH" >&2
  exit 1
fi
log "OK: Mac listener up on port $MAC_PORT"

MAC_SPKI_BEFORE="$(harness_identity_spki)"
if [ -z "$MAC_SPKI_BEFORE" ]; then
  log "FAIL: no harness-identity-spki line from the Mac app"
  exit 1
fi
MAC_FP_B64="$(printf '%s' "$MAC_SPKI_BEFORE" | hex_to_base64url)"

start_client "$CLIENT_IDENTITY" "$E15_15_TMP_DIR/client.in" "$E15_15_TMP_DIR/client.out"
exec 3>"$E15_15_TMP_DIR/client.in"
exec 4<"$E15_15_TMP_DIR/client.out"

client_startup_1="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: JVM client never printed its startup identity line"
  exit 1
}
case "$client_startup_1" in
  "harness-identity-spki: "*)
    CLIENT_SPKI_1="${client_startup_1#harness-identity-spki: }"
    ;;
  *)
    log "FAIL: JVM client unexpected startup line: $client_startup_1"
    exit 1
    ;;
esac

# --- Criterion 1: seeded trust record, client completes handshake ------------------------------

# Seeding writes to the same on-disk file keychain the running listener has open; stop the
# listener first (matching mac-driver.sh's own self-test ordering) to avoid concurrent access,
# then relaunch the identical, un-rebuilt binary on the same port.
harness_kill
seed_fixture_path="$E15_15_TMP_DIR/seed-client.json"
write_seed_fixture "$CLIENT_SPKI_1" "$seed_fixture_path"
if ! harness_seed_trust "$seed_fixture_path"; then
  log "FAIL: -HarnessSeedTrust failed"
  FAILED=1
fi
harness_launch "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up after seeding trust"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")"; then
    case "$response" in
      "OK CONNECTED")
        log "OK: jvmHarness_seededTrustRecord_clientCompletesHandshake"
        ;;
      *)
        log "FAIL: jvmHarness_seededTrustRecord_clientCompletesHandshake expected \"OK CONNECTED\", got: $response"
        FAILED=1
        ;;
    esac
  else
    log "FAIL: jvmHarness_seededTrustRecord_clientCompletesHandshake -- no response within ${CONNECT_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
  echo "DISCONNECT" >&3
  read_response "$STARTUP_TIMEOUT_SECONDS" >/dev/null || true
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

# --- Criterion 3 (harness order): restart both processes, same identity, handshake succeeds ----

harness_kill
TRUST_RECORDS="$(harness_list_trust)"
TRUST_COUNT="$(printf '%s\n' "$TRUST_RECORDS" | grep -c '^harness-trust-record: ' || true)"
if [ "$TRUST_COUNT" -ne 1 ]; then
  log "FAIL: expected exactly one trust record before restart, found $TRUST_COUNT"
  printf '%s\n' "$TRUST_RECORDS" >&2
  FAILED=1
fi
TRUSTED_FP_HEX="$(printf '%s\n' "$TRUST_RECORDS" | sed -n 's/^harness-trust-record: //p')"
if [ "$TRUSTED_FP_HEX" != "$CLIENT_SPKI_1" ]; then
  log "FAIL: trust record ($TRUSTED_FP_HEX) != client identity ($CLIENT_SPKI_1)"
  FAILED=1
fi

harness_launch "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up after restart"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

MAC_SPKI_AFTER="$(harness_identity_spki)"
if [ -z "$MAC_SPKI_AFTER" ] || [ "$MAC_SPKI_AFTER" != "$MAC_SPKI_BEFORE" ]; then
  log "FAIL: Mac identity SPKI changed across restart ('$MAC_SPKI_BEFORE' != '$MAC_SPKI_AFTER')"
  FAILED=1
fi

start_client "$CLIENT_IDENTITY" "$E15_15_TMP_DIR/client2.in" "$E15_15_TMP_DIR/client2.out"
exec 3>"$E15_15_TMP_DIR/client2.in"
exec 4<"$E15_15_TMP_DIR/client2.out"

client_startup_2="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: relaunched JVM client never printed its startup identity line"
  FAILED=1
}
if [ "$client_startup_2" != "$client_startup_1" ]; then
  log "FAIL: relaunched JVM client identity changed ($client_startup_2 != $client_startup_1)"
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")"; then
    case "$response" in
      "OK CONNECTED")
        log "OK: jvmHarness_restartBothProcesses_sameIdentityAndHandshakeSucceeds"
        ;;
      *)
        log "FAIL: jvmHarness_restartBothProcesses_sameIdentityAndHandshakeSucceeds expected \"OK CONNECTED\", got: $response"
        FAILED=1
        ;;
    esac
  else
    log "FAIL: jvmHarness_restartBothProcesses_sameIdentityAndHandshakeSucceeds -- no response within ${CONNECT_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
  echo "DISCONNECT" >&3
  read_response "$STARTUP_TIMEOUT_SECONDS" >/dev/null || true
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

# --- Criterion 2: trust store cleared, the same client's handshake is rejected -----------------
#
# A fresh process, but the same persisted identity file (same SPKI) as criteria 1/3 -- proving
# clearing revoked *that* identity's access, without inheriting any leftover coroutine/socket state
# from the previous CONNECT/DISCONNECT above.

harness_kill
if ! harness_clear_trust; then
  log "FAIL: -HarnessClearTrust exited non-zero"
  FAILED=1
fi
harness_launch "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up after clearing trust"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

start_client "$CLIENT_IDENTITY" "$E15_15_TMP_DIR/client3.in" "$E15_15_TMP_DIR/client3.out"
exec 3>"$E15_15_TMP_DIR/client3.in"
exec 4<"$E15_15_TMP_DIR/client3.out"

client_startup_3="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: third JVM client never printed its startup identity line"
  FAILED=1
}
if [ "$client_startup_3" != "$client_startup_1" ]; then
  log "FAIL: third JVM client identity differs ($client_startup_3 != $client_startup_1)"
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$REJECT_TIMEOUT_SECONDS")"; then
    case "$response" in
      "ERROR "*)
        log "OK: jvmHarness_clearedTrustStore_handshakeRejected: $response"
        ;;
      *)
        log "FAIL: jvmHarness_clearedTrustStore_handshakeRejected expected an ERROR, got: $response"
        FAILED=1
        ;;
    esac
  else
    log "FAIL: jvmHarness_clearedTrustStore_handshakeRejected -- no response within ${REJECT_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-

if [ "$FAILED" -ne 0 ]; then
  log "e15-15 integration FAILED"
  exit 1
fi
log "e15-15 integration OK"
exit 0
