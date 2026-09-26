#!/usr/bin/env bash
# E12-13: JVM client (E15-21) vs. the real macOS NWListener server (E12-01/E12-02), driven end to
# end through the E15-15 join: the real Mac app under `tools/harness/mac-driver.sh` (D-75 file
# keychain, never the login keychain, never signed, built once) and the real JVM harness client
# CLI (`android/harness/jvm-client`, built once) talking real mTLS on 127.0.0.1 only. The Android
# app itself never listens; only this script's JVM client ever dials out (invariant 4).
#
# Scenario A (positive, acceptance #1): client A's identity is seeded into the Mac trust store,
# then pinned-CONNECTs to the Mac's real SPKI -- `ConnectionState.Ready` (TLS 1.3 mTLS complete
# plus the E12-15 VersionHello exchange, see core/protocol/connection/ConnectionState.kt's state
# diagram) must arrive within 5 s, enforced by a bounded `read -t` on the CLI's response line.
#
# Scenario B (negative, "wrong pin"): a second, never-seeded client CONNECTs pinned to a random
# fingerprint instead of the Mac's real one -- the client's own PinningTrustManager must reject the
# server certificate before any application data is exchanged.
#
# Scenario C (negative, acceptance #3, "unknown client"): the same never-seeded client B then
# CONNECTs pinned correctly to the Mac's real SPKI -- the Mac's PeerVerifier must reject B's
# uncertified client certificate, so the handshake still fails and Ready is never reached.
#
# Both negative cases fail at the mTLS layer, strictly before `ConnectionState.HelloExchange`
# (which only exists post-handshake), satisfying the backlog's "never reaches HelloExchange".
#
# Acceptance #4 ("if the macOS runner or server app is unavailable, the job fails, not skipped")
# is this script's own unconditional `exit 1` on a non-Darwin host or a failed Mac app build --
# see the top-of-script guard and `harness_init` below.
#
# E12-12: the Mac side now wires an admitted, TLS-ready `NWListener` connection into a real
# session -- `NWConnectionByteStreamConnection` (`ByteStreamConnection`'s real Network.framework
# adapter) feeds a `ChannelMultiplexer` + `ConnectionStateMachine`, runs `VersionHandshake`, and
# registers the resulting session in `ControlSessionRegistry` under the peer's SPKI fingerprint
# (correlated via `PeerVerifier`'s `onDecision` hook, `ListenerFactory.swift`). All three scenarios
# pass.
set -uo pipefail

E12_13_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E12_13_ROOT/android"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
CONNECT_TIMEOUT_SECONDS=5
REJECT_TIMEOUT_SECONDS=15
STARTUP_TIMEOUT_SECONDS=10

# shellcheck source=../mac-driver.sh
source "$E12_13_ROOT/tools/harness/mac-driver.sh"

E12_13_TMP_DIR=""
E12_13_CLASSPATH=""
CLIENT_PIDS=()
FAILED=0

log() { echo "e12-13: $*" >&2; }

cleanup() {
  local pid
  for pid in "${CLIENT_PIDS[@]:-}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
    fi
  done
  # Best-effort: fds may already be closed by the scenario that opened them.
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  harness_cleanup
  if [ -n "$E12_13_TMP_DIR" ] && [ -d "$E12_13_TMP_DIR" ]; then
    rm -rf "$E12_13_TMP_DIR"
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
  "displayName": "e12-13 jvm harness client",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
}

# Starts a fresh JVM harness client process with its own identity file, piped through the fifos at
# $2 (stdin) / $3 (stdout+stderr); appends its pid to CLIENT_PIDS. Does not open either fifo end --
# callers do that themselves so multiple clients' fds can coexist under distinct fd numbers.
start_client() {
  local identity_file="$1"
  local in_fifo="$2"
  local out_fifo="$3"
  mkfifo "$in_fifo" "$out_fifo"
  "$JAVA_BIN" -cp "$E12_13_CLASSPATH" "$JVM_MAIN_CLASS" --identity-file "$identity_file" \
    <"$in_fifo" >"$out_fifo" 2>&1 &
  CLIENT_PIDS+=("$!")
}

# Reads one line from fd 4 (a client's stdout) with a bounded timeout; prints it and returns 0, or
# returns 1 on timeout/EOF. Every scenario's pass/fail check goes through this, so a hung handshake
# fails the scenario instead of hanging the script.
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
if ! E12_13_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not build/resolve the jvm-client runtime classpath"
  exit 1
fi
E12_13_CLASSPATH="${E12_13_CLASSPATH%:}"

E12_13_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e12-13.XXXXXX")"

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

MAC_SPKI_HEX="$(harness_identity_spki)"
if [ -z "$MAC_SPKI_HEX" ]; then
  log "FAIL: no harness-identity-spki line from the Mac app"
  exit 1
fi
MAC_FP_B64="$(printf '%s' "$MAC_SPKI_HEX" | hex_to_base64url)"

# --- Scenario A: seeded trust, positive handshake ---------------------------------------------

CLIENT_A_IDENTITY="$E12_13_TMP_DIR/client-a-identity.bin"
start_client "$CLIENT_A_IDENTITY" "$E12_13_TMP_DIR/client-a.in" "$E12_13_TMP_DIR/client-a.out"
exec 3>"$E12_13_TMP_DIR/client-a.in"
exec 4<"$E12_13_TMP_DIR/client-a.out"

client_a_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: client A never printed its startup identity line"
  FAILED=1
}
case "$client_a_startup" in
  "harness-identity-spki: "*)
    CLIENT_A_SPKI_HEX="${client_a_startup#harness-identity-spki: }"
    ;;
  *)
    log "FAIL: client A unexpected startup line: $client_a_startup"
    FAILED=1
    ;;
esac

if [ "$FAILED" -eq 0 ]; then
  # Seeding writes to the same on-disk file keychain the running listener has open; stop the
  # listener first (matching mac-driver.sh's own self-test ordering) to avoid concurrent access,
  # then relaunch the identical, un-rebuilt binary on the same port.
  harness_kill
  seed_fixture_path="$E12_13_TMP_DIR/seed-client-a.json"
  write_seed_fixture "$CLIENT_A_SPKI_HEX" "$seed_fixture_path"
  if ! harness_seed_trust "$seed_fixture_path"; then
    log "FAIL: -HarnessSeedTrust for client A failed"
    FAILED=1
  fi
  harness_launch "$MAC_PORT"
  if ! harness_wait_for_listening "$MAC_PORT"; then
    log "FAIL: Mac listener never came back up after seeding trust"
    cat "$HARNESS_LOG_PATH" >&2
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")"; then
    case "$response" in
      "OK CONNECTED")
        log "OK: scenario A -- seeded client reached Ready within ${CONNECT_TIMEOUT_SECONDS}s"
        ;;
      *)
        log "FAIL: scenario A expected \"OK CONNECTED\", got: $response"
        FAILED=1
        ;;
    esac
  else
    log "FAIL: scenario A -- no Ready/Failed response within ${CONNECT_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
  echo "DISCONNECT" >&3
  read_response "$STARTUP_TIMEOUT_SECONDS" >/dev/null || true
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-

# --- Scenarios B/C: never-seeded client, wrong pin then unknown client -------------------------

CLIENT_B_IDENTITY="$E12_13_TMP_DIR/client-b-identity.bin"
start_client "$CLIENT_B_IDENTITY" "$E12_13_TMP_DIR/client-b.in" "$E12_13_TMP_DIR/client-b.out"
exec 3>"$E12_13_TMP_DIR/client-b.in"
exec 4<"$E12_13_TMP_DIR/client-b.out"

read_response "$STARTUP_TIMEOUT_SECONDS" >/dev/null || {
  log "FAIL: client B never printed its startup identity line"
  FAILED=1
}

WRONG_FP_B64="$(openssl rand -hex 32 | hex_to_base64url)"
echo "CONNECT 127.0.0.1 $MAC_PORT $WRONG_FP_B64" >&3
if response="$(read_response "$REJECT_TIMEOUT_SECONDS")"; then
  case "$response" in
    "ERROR "*)
      log "OK: scenario B -- wrong pin rejected client-side: $response"
      ;;
    *)
      log "FAIL: scenario B (wrong pin) expected an ERROR, got: $response"
      FAILED=1
      ;;
  esac
else
  log "FAIL: scenario B (wrong pin) -- no response within ${REJECT_TIMEOUT_SECONDS}s"
  FAILED=1
fi

echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
if response="$(read_response "$REJECT_TIMEOUT_SECONDS")"; then
  case "$response" in
    "ERROR "*)
      log "OK: scenario C -- unseeded client rejected server-side: $response"
      ;;
    *)
      log "FAIL: scenario C (unknown client) expected an ERROR, got: $response"
      FAILED=1
      ;;
  esac
else
  log "FAIL: scenario C (unknown client) -- no response within ${REJECT_TIMEOUT_SECONDS}s"
  FAILED=1
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-

if [ "$FAILED" -ne 0 ]; then
  log "e12-13 integration FAILED"
  exit 1
fi
log "e12-13 integration OK"
exit 0
