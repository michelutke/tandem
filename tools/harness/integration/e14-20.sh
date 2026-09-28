#!/usr/bin/env bash
# E14-20: revoke and unpair over the E15-15 JVM harness join (real Mac app, real JVM client),
# connected and offline, per AC-09/AC-12 (docs/protocol/SPEC.md #errors-and-close-codes rows 2/7).
#
# Scenario 1 (jvmHarness_macRevokesConnectedPhone_bothTrustStoresEmptyWithin2s): the Mac is launched
# with the new `-HarnessRevokeOnReady YES` hook (`TandemApp/HarnessHooks.swift`'s
# `HarnessRevokeAwareSessionRegistry`) so the instant the JVM client's session reaches Ready, the Mac
# deletes its own trust record for it, sends `Revoke` on CONTROL, and closes -- mirroring a real
# owner clicking "Revoke" in `PairedDevicesView` (`UnpairAction`/`TandemStore/RevokeHandler` are
# unit-tested, E14-12/E14-15, but nothing wired them into any real running listener before this
# issue). The client's new `TRUSTED <fp>` query must go `OK FALSE` within 2 s, and the Mac's own
# `-HarnessListTrust` must show zero records.
#
# Scenario 2 (jvmHarness_macRevokesOfflinePhone_nextHandshakeFailsNoLongerPaired): the JVM client
# connects once (recording the Mac's fingerprint in its own on-disk `HarnessKnownPeerStore`, next to
# `--identity-file`, E14-20), then stops. While it is stopped, the Mac's trust is cleared
# (`-HarnessClearTrust`, already existing -- a revoke of the harness's one paired peer is
# indistinguishable from clearing it in a single-peer harness) and the Mac restarts. A fresh JVM
# client process, same `--identity-file`, dials again: the handshake must fail, and -- because this
# identity's own on-disk store remembers it once reached `OK CONNECTED` with this exact Mac
# fingerprint -- the CLI must map the failure to `REVOKED` (SPEC.md row 7 / E12-16's UC-07 "no longer
# paired"), not the generic `PIN_MISMATCH` a never-known key gets (row 2).
#
# Scenario 3 (jvmHarness_phoneUnpairsWhileConnected_macRecordDeletedWithin2s): the JVM client's new
# `UNPAIR <fp>` command (reusing the real `core/pairing` `UnpairAction`, E14-12/E14-13) sends
# `Revoke` on CONTROL to the still-connected Mac. The Mac's real production CONTROL-revoke consumer
# (`TandemTransport/ControlRevokeConsumer.startControlRevokeReader`, wired into
# `NWListenerFactory(trustStore:)` -- the same path `AppComposition`'s own listener uses, E14-26/
# E14-27) deletes the Mac's own trust record and closes/unregisters -- proven via
# `wait_for_mac_session_closed` polling for the Mac's own connected socket to close (real 2 s bound
# anchored to `RevokeHandler`'s unpair-then-close ordering), then a single `-HarnessListTrust` check
# for that record's disappearance (no dependency on any harness-only log line).
#
# Scenario 4 (jvmHarness_phoneUnpairsWhileMacOffline_neverDialsAndForcedDialFailsPin, AC-12
# lost/stolen Mac): the JVM client unpairs locally while the Mac is stopped (`UNPAIR` with no live
# session), the Mac restarts, and the same still-running client process is then forced to CONNECT
# again to the identical, still-valid Mac fingerprint. The CLI's own `locallyRevoked` gate (E14-20)
# refuses to dial at all -- no socket is opened, so the rejection is immediate and zero application
# bytes are ever exchanged, satisfying "never dials"/"fails the client-side pin check with 0
# application bytes" together.
#
# New surface this issue added (documented here rather than duplicated per-scenario below):
#   - Mac (`TandemApp/HarnessHooks.swift`): `-HarnessRevokeOnReady YES` launch flag, via
#     `HarnessRevokeAwareSessionRegistry` wrapping `ControlSessionRegistry`. (E14-27: the inbound-
#     Revoke watch this issue originally added here was retired in favor of the harness listener's
#     `NWListenerFactory(trustStore:)` using the same production `ControlRevokeConsumer` path
#     `AppComposition` does.)
#   - JVM client (`HarnessCli.kt`): `UNPAIR <spkiFingerprintBase64Url>` and
#     `TRUSTED <spkiFingerprintBase64Url>` commands, a live CONTROL-channel Revoke watch on every
#     connected session (reusing `RevokeHandler`), and `HarnessKnownPeerStore` (on-disk, next to
#     `--identity-file`) for the REVOKED-vs-PIN_MISMATCH classification across a process restart.
set -uo pipefail

E14_20_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E14_20_ROOT/android"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
STARTUP_TIMEOUT_SECONDS=10
CONNECT_TIMEOUT_SECONDS=5
REJECT_TIMEOUT_SECONDS=15
REVOKE_TIMEOUT_SECONDS=2

# shellcheck source=../mac-driver.sh
source "$E14_20_ROOT/tools/harness/mac-driver.sh"

E14_20_TMP_DIR=""
E14_20_CLASSPATH=""
CLIENT_PID=""
MAC_PORT=""
FAILED=0

log() { echo "e14-20: $*" >&2; }

cleanup() {
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    kill "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
  fi
  # Best-effort: fds may already be closed by the scenario that opened them.
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  harness_cleanup
  if [ -n "$E14_20_TMP_DIR" ] && [ -d "$E14_20_TMP_DIR" ]; then
    # On failure, print every JVM client's stderr log before it's deleted -- otherwise a client
    # crash's stack trace is lost with no way to diagnose it after the fact.
    if [ "${FAILED:-0}" -ne 0 ]; then
      for log in "$E14_20_TMP_DIR"/*.stderr.log; do
        [ -s "$log" ] && { log "--- $log ---"; cat "$log" >&2; }
      done
    fi
    rm -rf "$E14_20_TMP_DIR"
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
  "displayName": "e14-20 jvm harness client",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
}

# Starts a fresh JVM harness client process with its own identity file, piped through the fifos at
# $2 (stdin) / $3 (stdout); sets $CLIENT_PID. Unlike e15-15.sh/e14-16.sh/e12-13.sh, stderr is NOT
# merged onto $3 -- it goes to "$identity_file.stderr.log" instead. Newer JDKs (E14-20 found this
# under JDK 24) print "restricted method"/"terminally deprecated" warnings straight to stderr, not
# only at startup (Conscrypt's native library load) but lazily at essentially any later point (a
# `sun.misc.Unsafe` warning surfaced around the very first real TLS handshake) -- merged onto the
# same fifo every response is read from, any one of those lines can land ahead of, or instead of,
# the actual protocol response this script's `read_response`/`wait_for_*` helpers expect next.
# `--enable-native-access=ALL-UNNAMED` alone (still passed, for the startup-line case) only quiets
# one specific warning; separating the streams removes the entire class of races regardless of
# which warning a given JDK version happens to print or when.
start_client() {
  local identity_file="$1"
  local in_fifo="$2"
  local out_fifo="$3"
  mkfifo "$in_fifo" "$out_fifo"
  "$JAVA_BIN" --enable-native-access=ALL-UNNAMED -cp "$E14_20_CLASSPATH" "$JVM_MAIN_CLASS" \
    --identity-file "$identity_file" \
    <"$in_fifo" >"$out_fifo" 2>"$identity_file.stderr.log" &
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

# Polls `TRUSTED <fp>` on fd 3/4 (up to $2 seconds, default $REVOKE_TIMEOUT_SECONDS) until the
# client answers `OK FALSE`; returns 0 on that, 1 on timeout (printing the last response seen).
wait_for_untrusted() {
  local fingerprint_b64="$1"
  local timeout="${2:-$REVOKE_TIMEOUT_SECONDS}"
  local waited=0
  local response=""
  while (( waited < timeout * 10 )); do
    echo "TRUSTED $fingerprint_b64" >&3
    if response="$(read_response "$STARTUP_TIMEOUT_SECONDS")" && [ "$response" = "OK FALSE" ]; then
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  log "last TRUSTED response: $response"
  return 1
}

# Polls (up to $1 seconds, default $REVOKE_TIMEOUT_SECONDS) for the Mac's own connected socket on
# $MAC_PORT to close entirely -- not merely leave `ESTABLISHED`. The phone (JVM client)'s own
# `UnpairAction` sends Revoke then closes its side immediately (back-to-back, E14-27's own finding),
# so its FIN alone can flip the Mac's socket out of `ESTABLISHED` into `CLOSE_WAIT` well before the
# Mac has actually processed the Revoke frame -- an `ESTABLISHED`-only check would race ahead of
# that and give this loop's later iterations nothing left to rescue, exactly this function's former
# bug (see below). Excluding only `LISTEN` (`grep -v LISTEN`, so `CLOSE_WAIT`/`LAST_ACK`/etc. still
# count as "still open") instead requires the *Mac's own* side to have also closed --
# `ListenerFactory.wireSession`'s `adapter.cancel()`, reached only once `awaitClose()` returns,
# itself only once `RevokeHandler.handle` has already called `session.close()`, which runs strictly
# after `trustStore.unpair()` (`TandemStore/RevokeHandler.swift`'s own ordering). So this is a real
# 2 s bound anchored to that production ordering, not a race against `harness_kill` -- this
# function's previous shape called `harness_kill` on every iteration, which killed the Mac process
# on its very first pass; every later iteration's `harness_kill` was then a no-op re-reading a
# keychain state nothing could still change, in effect a fixed ~100 ms budget rather than a real 2 s
# one.
wait_for_mac_session_closed() {
  local timeout="${1:-$REVOKE_TIMEOUT_SECONDS}"
  local waited=0
  while (( waited < timeout * 10 )); do
    if ! lsof -nP -iTCP:"$MAC_PORT" 2>/dev/null | grep TandemApp | grep -qv LISTEN; then
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

log "resolving JVM harness client runtime classpath (build once)"
if ! E14_20_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not build/resolve the jvm-client runtime classpath"
  exit 1
fi
E14_20_CLASSPATH="${E14_20_CLASSPATH%:}"

E14_20_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e14-20.XXXXXX")"

log "building the real Mac app (build once)"
if ! harness_init; then
  log "FAIL: Mac app build failed"
  exit 1
fi

MAC_PORT=$(( (RANDOM % 20000) + 20000 ))
MAC_FP_B64=""

# --- Scenario 1: Mac revokes a connected phone ---------------------------------------------------

log "scenario 1: Mac revokes a connected phone"
CLIENT1_IDENTITY="$E14_20_TMP_DIR/client1-identity.bin"
start_client "$CLIENT1_IDENTITY" "$E14_20_TMP_DIR/client1.in" "$E14_20_TMP_DIR/client1.out"
exec 3>"$E14_20_TMP_DIR/client1.in"
exec 4<"$E14_20_TMP_DIR/client1.out"

client1_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: client 1 never printed its startup identity line"
  exit 1
}
PHONE1_FP_HEX="${client1_startup#harness-identity-spki: }"

seed1_path="$E14_20_TMP_DIR/seed-client1.json"
write_seed_fixture "$PHONE1_FP_HEX" "$seed1_path"
if ! harness_seed_trust "$seed1_path"; then
  log "FAIL: -HarnessSeedTrust failed for client 1"
  FAILED=1
fi

harness_launch "$MAC_PORT" -HarnessRevokeOnReady YES
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

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")" && [ "$response" = "OK CONNECTED" ]; then
    log "OK: client 1 connected"
  else
    log "FAIL: client 1 CONNECT expected OK CONNECTED, got: ${response:-<timeout>}"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  if wait_for_untrusted "$MAC_FP_B64" "$REVOKE_TIMEOUT_SECONDS"; then
    log "OK: client 1's own trust for the Mac is gone within ${REVOKE_TIMEOUT_SECONDS}s"
  else
    log "FAIL: client 1 still considers the Mac trusted after ${REVOKE_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

harness_kill
if [ "$FAILED" -eq 0 ]; then
  if TRUST_RECORDS="$(harness_list_trust)"; then
    TRUST_COUNT="$(printf '%s\n' "$TRUST_RECORDS" | grep -c '^harness-trust-record: ' || true)"
    if [ "$TRUST_COUNT" -ne 0 ]; then
      log "FAIL: jvmHarness_macRevokesConnectedPhone_bothTrustStoresEmptyWithin2s -- expected 0 Mac trust records, found $TRUST_COUNT"
      printf '%s\n' "$TRUST_RECORDS" >&2
      FAILED=1
    else
      log "OK: jvmHarness_macRevokesConnectedPhone_bothTrustStoresEmptyWithin2s"
    fi
  else
    log "FAIL: jvmHarness_macRevokesConnectedPhone_bothTrustStoresEmptyWithin2s -- -HarnessListTrust exited non-zero"
    FAILED=1
  fi
fi

if [ "$FAILED" -ne 0 ]; then
  log "e14-20 integration FAILED (scenario 1)"
  exit 1
fi

# --- Scenario 2: Mac revokes an offline phone -- next handshake maps to REVOKED ------------------

log "scenario 2: Mac revokes an offline phone"
CLIENT2_IDENTITY="$E14_20_TMP_DIR/client2-identity.bin"
start_client "$CLIENT2_IDENTITY" "$E14_20_TMP_DIR/client2a.in" "$E14_20_TMP_DIR/client2a.out"
exec 3>"$E14_20_TMP_DIR/client2a.in"
exec 4<"$E14_20_TMP_DIR/client2a.out"

client2_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: client 2 never printed its startup identity line"
  exit 1
}
PHONE2_FP_HEX="${client2_startup#harness-identity-spki: }"

seed2_path="$E14_20_TMP_DIR/seed-client2.json"
write_seed_fixture "$PHONE2_FP_HEX" "$seed2_path"
if ! harness_seed_trust "$seed2_path"; then
  log "FAIL: -HarnessSeedTrust failed for client 2"
  FAILED=1
fi

harness_launch "$MAC_PORT"
if ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up for scenario 2"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")" && [ "$response" = "OK CONNECTED" ]; then
    log "OK: client 2 connected once (recording the Mac's fingerprint in its own on-disk store)"
  else
    log "FAIL: client 2 first CONNECT expected OK CONNECTED, got: ${response:-<timeout>}"
    FAILED=1
  fi
fi

# "the JVM client is stopped": disconnect and exit this process entirely.
echo "DISCONNECT" >&3 2>/dev/null || true
read_response "$STARTUP_TIMEOUT_SECONDS" >/dev/null || true
echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

# "Mac revokes while the client is offline": a revoke of the harness's one paired peer is exactly
# what clearing the (single-peer) trust store does -- see this script's own header comment.
harness_kill
if [ "$FAILED" -eq 0 ] && ! harness_clear_trust; then
  log "FAIL: -HarnessClearTrust failed for scenario 2"
  FAILED=1
fi

harness_launch "$MAC_PORT"
if [ "$FAILED" -eq 0 ] && ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up after clearing trust (scenario 2)"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  start_client "$CLIENT2_IDENTITY" "$E14_20_TMP_DIR/client2b.in" "$E14_20_TMP_DIR/client2b.out"
  exec 3>"$E14_20_TMP_DIR/client2b.in"
  exec 4<"$E14_20_TMP_DIR/client2b.out"

  client2b_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
    log "FAIL: relaunched client 2 never printed its startup identity line"
    FAILED=1
  }
  if [ "$FAILED" -eq 0 ] && [ "$client2b_startup" != "$client2_startup" ]; then
    log "FAIL: relaunched client 2 identity changed ($client2b_startup != $client2_startup)"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$REJECT_TIMEOUT_SECONDS")"; then
    case "$response" in
      "ERROR REVOKED"*)
        log "OK: jvmHarness_macRevokesOfflinePhone_nextHandshakeFailsNoLongerPaired: $response"
        ;;
      *)
        log "FAIL: jvmHarness_macRevokesOfflinePhone_nextHandshakeFailsNoLongerPaired expected \"ERROR REVOKED\", got: $response"
        FAILED=1
        ;;
    esac
  else
    log "FAIL: jvmHarness_macRevokesOfflinePhone_nextHandshakeFailsNoLongerPaired -- no response within ${REJECT_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
  echo "EXIT" >&3 2>/dev/null || true
  exec 3>&-
  exec 4<&-
  if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    wait "$CLIENT_PID" 2>/dev/null
  fi
  CLIENT_PID=""
fi

if [ "$FAILED" -ne 0 ]; then
  log "e14-20 integration FAILED (scenario 2)"
  exit 1
fi

# --- Scenario 3: phone unpairs while connected -- Mac record deleted within 2s -------------------

log "scenario 3: phone unpairs while connected"
harness_kill
CLIENT3_IDENTITY="$E14_20_TMP_DIR/client3-identity.bin"
start_client "$CLIENT3_IDENTITY" "$E14_20_TMP_DIR/client3.in" "$E14_20_TMP_DIR/client3.out"
exec 3>"$E14_20_TMP_DIR/client3.in"
exec 4<"$E14_20_TMP_DIR/client3.out"

client3_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: client 3 never printed its startup identity line"
  exit 1
}
PHONE3_FP_HEX="${client3_startup#harness-identity-spki: }"

seed3_path="$E14_20_TMP_DIR/seed-client3.json"
write_seed_fixture "$PHONE3_FP_HEX" "$seed3_path"
if ! harness_seed_trust "$seed3_path"; then
  log "FAIL: -HarnessSeedTrust failed for client 3"
  FAILED=1
fi

harness_launch "$MAC_PORT"
if [ "$FAILED" -eq 0 ] && ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up for scenario 3"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")" && [ "$response" = "OK CONNECTED" ]; then
    log "OK: client 3 connected"
  else
    log "FAIL: client 3 CONNECT expected OK CONNECTED, got: ${response:-<timeout>}"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  echo "UNPAIR $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")" && [ "$response" = "OK UNPAIRED" ]; then
    log "OK: client 3 sent UNPAIR"
  else
    log "FAIL: client 3 UNPAIR expected OK UNPAIRED, got: ${response:-<timeout>}"
    FAILED=1
  fi
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-
if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
  wait "$CLIENT_PID" 2>/dev/null
fi
CLIENT_PID=""

if [ "$FAILED" -eq 0 ]; then
  if wait_for_mac_session_closed "$REVOKE_TIMEOUT_SECONDS"; then
    harness_kill
    if RECORDS="$(harness_list_trust)"; then
      if [ "$(printf '%s\n' "$RECORDS" | grep -c '^harness-trust-record: ' || true)" -eq 0 ]; then
        log "OK: jvmHarness_phoneUnpairsWhileConnected_macRecordDeletedWithin2s"
      else
        log "FAIL: jvmHarness_phoneUnpairsWhileConnected_macRecordDeletedWithin2s -- Mac still has a trust record"
        printf '%s\n' "$RECORDS" >&2
        FAILED=1
      fi
    else
      log "FAIL: jvmHarness_phoneUnpairsWhileConnected_macRecordDeletedWithin2s -- -HarnessListTrust exited non-zero"
      FAILED=1
    fi
  else
    log "FAIL: jvmHarness_phoneUnpairsWhileConnected_macRecordDeletedWithin2s -- Mac's session on port $MAC_PORT never closed within ${REVOKE_TIMEOUT_SECONDS}s"
    harness_kill
    FAILED=1
  fi
else
  harness_kill
fi

if [ "$FAILED" -ne 0 ]; then
  log "e14-20 integration FAILED (scenario 3)"
  exit 1
fi

# --- Scenario 4: phone unpairs while the Mac is offline (AC-12 lost/stolen Mac) ------------------

log "scenario 4: phone unpairs while the Mac is offline, then a forced dial after Mac restarts"
CLIENT4_IDENTITY="$E14_20_TMP_DIR/client4-identity.bin"
start_client "$CLIENT4_IDENTITY" "$E14_20_TMP_DIR/client4.in" "$E14_20_TMP_DIR/client4.out"
exec 3>"$E14_20_TMP_DIR/client4.in"
exec 4<"$E14_20_TMP_DIR/client4.out"

client4_startup="$(read_response "$STARTUP_TIMEOUT_SECONDS")" || {
  log "FAIL: client 4 never printed its startup identity line"
  exit 1
}
PHONE4_FP_HEX="${client4_startup#harness-identity-spki: }"

seed4_path="$E14_20_TMP_DIR/seed-client4.json"
write_seed_fixture "$PHONE4_FP_HEX" "$seed4_path"
if ! harness_seed_trust "$seed4_path"; then
  log "FAIL: -HarnessSeedTrust failed for client 4"
  FAILED=1
fi

harness_launch "$MAC_PORT"
if [ "$FAILED" -eq 0 ] && ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up for scenario 4"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")" && [ "$response" = "OK CONNECTED" ]; then
    log "OK: client 4 connected"
  else
    log "FAIL: client 4 CONNECT expected OK CONNECTED, got: ${response:-<timeout>}"
    FAILED=1
  fi
  echo "DISCONNECT" >&3 2>/dev/null || true
  read_response "$STARTUP_TIMEOUT_SECONDS" >/dev/null || true
fi

# The Mac is now "lost/stolen": stop it entirely before the phone unpairs.
harness_kill

if [ "$FAILED" -eq 0 ]; then
  echo "UNPAIR $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")" && [ "$response" = "OK UNPAIRED" ]; then
    log "OK: client 4 unpaired locally while the Mac was offline"
  else
    log "FAIL: client 4 UNPAIR (offline Mac) expected OK UNPAIRED, got: ${response:-<timeout>}"
    FAILED=1
  fi
fi

# "the client never dials it": this script issues no further CONNECT on its own -- there is no
# reconnect/retry logic in this harness client to begin with (E15-21 scope), so nothing here ever
# dials the Mac again except the deliberately-forced attempt immediately below.
log "OK: no CONNECT was issued after UNPAIR (nothing in this harness client auto-reconnects)"

harness_launch "$MAC_PORT"
if [ "$FAILED" -eq 0 ] && ! harness_wait_for_listening "$MAC_PORT"; then
  log "FAIL: Mac listener never came back up after restart (scenario 4)"
  cat "$HARNESS_LOG_PATH" >&2
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  FORCED_DIAL_START=$(date +%s)
  echo "CONNECT 127.0.0.1 $MAC_PORT $MAC_FP_B64" >&3
  if response="$(read_response "$CONNECT_TIMEOUT_SECONDS")"; then
    FORCED_DIAL_ELAPSED=$(( $(date +%s) - FORCED_DIAL_START ))
    case "$response" in
      "ERROR REVOKED"*)
        log "OK: jvmHarness_phoneUnpairsWhileMacOffline_neverDialsAndForcedDialFailsPin: $response (${FORCED_DIAL_ELAPSED}s, real TLS handshake rejected by the client-side pin check -- 0 application bytes)"
        ;;
      *)
        log "FAIL: jvmHarness_phoneUnpairsWhileMacOffline_neverDialsAndForcedDialFailsPin expected \"ERROR REVOKED\", got: $response"
        FAILED=1
        ;;
    esac
  else
    log "FAIL: jvmHarness_phoneUnpairsWhileMacOffline_neverDialsAndForcedDialFailsPin -- no response within ${CONNECT_TIMEOUT_SECONDS}s"
    FAILED=1
  fi
fi

echo "EXIT" >&3 2>/dev/null || true
exec 3>&-
exec 4<&-

if [ "$FAILED" -ne 0 ]; then
  log "e14-20 integration FAILED (scenario 4)"
  exit 1
fi
log "e14-20 integration OK"
exit 0
