#!/usr/bin/env bash
# tools/mitm-lab/e15-09-pairing-abuse/lib/e15-09-common.sh -- E15-09 shared scenario library.
#
# Each E15-09 scenario is self-contained (mirroring the E15-08 self-test scenarios' own "ignores
# MITM_TARGET_HOST/PORT" convention): it builds and launches its own real Mac app (`tools/harness/
# mac-driver.sh`, D-75 file keychain) with a fresh pairing window open, and drives it through the
# real JVM harness client CLI (`android/harness/jvm-client`, E15-21/E15-22/E15-15), extended by this
# issue with `RAWOPEN`/`RAWSEND`/`RAWSENDPROOF`/`RAWREVOKE`/`RAWCLOSE` -- low-level pairing-candidate
# commands that deliberately bypass the real `PairingStateMachine` so a scenario can construct a
# wrong, replayed, or malformed `PairRequest` it would never produce (see `HarnessCli.kt`'s kdoc on
# those commands). A shared Mac process cannot serve more than one scenario: the pairing window is
# single-use and only ever opened at Mac-process launch (`-HarnessOpenPairingWindow YES`), so each
# scenario needing a fresh window launches its own Mac process, exactly like `tools/harness/
# integration/e14-16.sh`/`e14-20.sh`/`e15-15.sh` already do for their own scenarios.
#
# Source this file, call `e15_09_setup` (after `trap e15_09_teardown EXIT`), then use
# `e15_09_start_client`/`e15_09_read`/`e15_09_send`/`e15_09_stop_client` (fd 3/4, one client) and, if
# a scenario needs a second concurrent client (E15-09 scenario 8), `e15_09_start_client2`/
# `e15_09_read2`/`e15_09_send2`/`e15_09_stop_client2` (fd 5/6).
set -uo pipefail

E15_09_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E15_09_ANDROID_DIR="$E15_09_LIB_ROOT/android"
E15_09_JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
E15_09_JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"

E15_09_STARTUP_TIMEOUT_SECONDS=10
E15_09_LOG_WAIT_TIMEOUT_SECONDS=15
# Comfortably exceeds RAW_CHALLENGE_TIMEOUT_MS (10s, HarnessCli.kt's rawOpen) plus handshake time: an
# already-trusted identity's RAWOPEN only replies "OK OPENED NOCHALLENGE" after that 10s wait for a
# non-Heartbeat frame elapses, so a shorter read timeout here loses that race and times out before the
# real response ever arrives (see e15_09_rawopen's kdoc).
E15_09_RAWOPEN_TIMEOUT_SECONDS=25

# shellcheck source=../../../harness/mac-driver.sh
source "$E15_09_LIB_ROOT/tools/harness/mac-driver.sh"

E15_09_TMP_DIR=""
E15_09_CLASSPATH=""
MAC_PORT=""
MAC_SPKI_HEX=""
MAC_FP_B64=""
SECRET_B64URL=""
QR_URI=""

CLIENT_PID=""
CLIENT2_PID=""

e15_09_log() { echo "e15-09: $*" >&2; }

# base64url (no padding) -> lowercase hex.
e15_09_b64url_to_hex() {
  local b64="$1"
  b64="${b64//-/+}"
  b64="${b64//_//}"
  case $(( ${#b64} % 4 )) in
    2) b64="${b64}==" ;;
    3) b64="${b64}=" ;;
  esac
  printf '%s' "$b64" | base64 -d | xxd -p -c 256 | tr -d '\n'
}

# lowercase hex -> base64url (no padding).
e15_09_hex_to_b64url() {
  printf '%s' "$1" | xxd -r -p | base64 | tr '+/' '-_' | tr -d '=\n'
}

# Extracts query field $2 (e.g. "s", "fp") from a `tandem://pair?...` URI $1 (SPEC.md #pairing "QR
# payload grammar"). No full grammar validation here -- this is a test driver reading a URI its own
# harness produced, not an untrusted parser.
e15_09_qr_field() {
  printf '%s' "$1" | sed -n "s/.*[?&]$2=\\([^&]*\\).*/\\1/p"
}

# Waits (up to $2 seconds, default $E15_09_LOG_WAIT_TIMEOUT_SECONDS) for a line matching regex $1 in
# the current Mac launch's log; prints the last matching line and returns 0, or returns 1 on timeout.
e15_09_wait_for_log_line() {
  local pattern="$1"
  local timeout="${2:-$E15_09_LOG_WAIT_TIMEOUT_SECONDS}"
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

# Builds the JVM harness client classpath once, builds+launches the real Mac app with a fresh
# pairing window open (auto-confirming Pair the instant a correct proof arrives -- irrelevant to
# every scenario here since none ever sends a correct proof to this window, except the
# once-legitimate setup pairing scenarios 1/6 perform themselves), and populates $MAC_PORT,
# $MAC_SPKI_HEX, $MAC_FP_B64, $QR_URI and $SECRET_B64URL. Exits 1 (printing to stderr, no OUTCOME
# line -- an infrastructure failure, not a scenario result) on any setup failure.
e15_09_setup() {
  if [ "$(uname)" != "Darwin" ]; then
    e15_09_log "this scenario requires the real macOS NWListener server -- not skipping"
    exit 1
  fi

  E15_09_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e15-09.XXXXXX")"

  e15_09_log "resolving JVM harness client runtime classpath (build once)"
  if ! E15_09_CLASSPATH="$(cd "$E15_09_ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
    e15_09_log "could not build/resolve the jvm-client runtime classpath"
    exit 1
  fi
  E15_09_CLASSPATH="${E15_09_CLASSPATH%:}"

  e15_09_log "building the real Mac app (build once)"
  if ! harness_init; then
    e15_09_log "Mac app build failed"
    exit 1
  fi

  MAC_PORT=$(( (RANDOM % 20000) + 20000 ))
  harness_launch "$MAC_PORT" -HarnessOpenPairingWindow YES -HarnessAutoConfirmPairing YES
  if ! harness_wait_for_listening "$MAC_PORT"; then
    e15_09_log "Mac listener never came up on port $MAC_PORT"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi

  MAC_SPKI_HEX="$(harness_identity_spki)"
  if [ -z "$MAC_SPKI_HEX" ]; then
    e15_09_log "no harness-identity-spki line from the Mac app"
    exit 1
  fi
  MAC_FP_B64="$(e15_09_hex_to_b64url "$MAC_SPKI_HEX")"

  local qr_line
  qr_line="$(e15_09_wait_for_log_line 'harness-pairing-qr-uri: .*')" || {
    e15_09_log "Mac app never printed its pairing QR URI"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  }
  QR_URI="${qr_line#harness-pairing-qr-uri: }"
  SECRET_B64URL="$(e15_09_qr_field "$QR_URI" s)"
  if [ -z "$SECRET_B64URL" ]; then
    e15_09_log "could not parse the pairing secret ('s' field) out of the QR URI: $QR_URI"
    exit 1
  fi
  e15_09_log "OK: Mac listening on $MAC_PORT, pairing window open"
}

# Kills any running client processes, the Mac app, and removes the temp dir. Safe to call multiple
# times and safe to call as an EXIT trap even if `e15_09_setup` failed partway.
e15_09_teardown() {
  e15_09_stop_client 2>/dev/null || true
  e15_09_stop_client2 2>/dev/null || true
  harness_cleanup
  if [ -n "$E15_09_TMP_DIR" ] && [ -d "$E15_09_TMP_DIR" ]; then
    for log in "$E15_09_TMP_DIR"/*.stderr.log; do
      [ -s "$log" ] && { e15_09_log "--- $log ---"; cat "$log" >&2; }
    done
    rm -rf "$E15_09_TMP_DIR"
  fi
}

# --- Primary client: fd 3 (stdin) / fd 4 (stdout+stderr) -----------------------------------------

CLIENT1_SPKI_HEX=""

e15_09_start_client() {
  local identity_file="$E15_09_TMP_DIR/client1-identity.bin"
  rm -f "$E15_09_TMP_DIR/client1.in" "$E15_09_TMP_DIR/client1.out"
  mkfifo "$E15_09_TMP_DIR/client1.in" "$E15_09_TMP_DIR/client1.out"
  # `tools/harness/integration/e14-20.sh` found that newer JDKs print "restricted method"/
  # "terminally deprecated" warnings (Conscrypt's native library load, and others later, e.g.
  # around the first real TLS handshake) straight to stderr at unpredictable points -- merged onto
  # the same fifo every response is read from, any one of those lines can land ahead of, or instead
  # of, the actual protocol response this library's `e15_09_read`/`e15_09_rawopen`/etc. expect next.
  # Separating the streams (stderr to its own log file, `--enable-native-access` to quiet the
  # loudest one at the source) removes the whole class of races, exactly as e14-20.sh's own comment
  # describes.
  "$E15_09_JAVA_BIN" --enable-native-access=ALL-UNNAMED -cp "$E15_09_CLASSPATH" "$E15_09_JVM_MAIN_CLASS" \
    --identity-file "$identity_file" \
    <"$E15_09_TMP_DIR/client1.in" >"$E15_09_TMP_DIR/client1.out" 2>"$identity_file.stderr.log" &
  CLIENT_PID=$!
  exec 3>"$E15_09_TMP_DIR/client1.in"
  exec 4<"$E15_09_TMP_DIR/client1.out"
  local startup
  startup="$(e15_09_read "$E15_09_STARTUP_TIMEOUT_SECONDS")" || {
    e15_09_log "client 1 never printed its startup identity line"
    exit 1
  }
  CLIENT1_SPKI_HEX="${startup#harness-identity-spki: }"
}

e15_09_read() {
  local timeout_seconds="$1"
  local line
  if IFS= read -r -t "$timeout_seconds" line <&4; then
    printf '%s\n' "$line"
    return 0
  fi
  return 1
}

e15_09_send() {
  echo "$1" >&3
}

e15_09_stop_client() {
  if [ -n "${CLIENT_PID:-}" ]; then
    echo "EXIT" >&3 2>/dev/null || true
    exec 3>&- || true
    exec 4<&- || true
    if kill -0 "$CLIENT_PID" 2>/dev/null; then
      kill "$CLIENT_PID" 2>/dev/null
      wait "$CLIENT_PID" 2>/dev/null
    fi
    CLIENT_PID=""
  fi
}

# --- Second concurrent client (scenario 8 only): fd 5 (stdin) / fd 6 (stdout+stderr) -------------

CLIENT2_SPKI_HEX=""

e15_09_start_client2() {
  local identity_file="$E15_09_TMP_DIR/client2-identity.bin"
  rm -f "$E15_09_TMP_DIR/client2.in" "$E15_09_TMP_DIR/client2.out"
  mkfifo "$E15_09_TMP_DIR/client2.in" "$E15_09_TMP_DIR/client2.out"
  # See `e15_09_start_client`'s comment: stderr must not share the fifo `e15_09_read2` reads from.
  "$E15_09_JAVA_BIN" --enable-native-access=ALL-UNNAMED -cp "$E15_09_CLASSPATH" "$E15_09_JVM_MAIN_CLASS" \
    --identity-file "$identity_file" \
    <"$E15_09_TMP_DIR/client2.in" >"$E15_09_TMP_DIR/client2.out" 2>"$identity_file.stderr.log" &
  CLIENT2_PID=$!
  exec 5>"$E15_09_TMP_DIR/client2.in"
  exec 6<"$E15_09_TMP_DIR/client2.out"
  local startup
  startup="$(e15_09_read2 "$E15_09_STARTUP_TIMEOUT_SECONDS")" || {
    e15_09_log "client 2 never printed its startup identity line"
    exit 1
  }
  CLIENT2_SPKI_HEX="${startup#harness-identity-spki: }"
}

e15_09_read2() {
  local timeout_seconds="$1"
  local line
  if IFS= read -r -t "$timeout_seconds" line <&6; then
    printf '%s\n' "$line"
    return 0
  fi
  return 1
}

e15_09_send2() {
  echo "$1" >&5
}

e15_09_stop_client2() {
  if [ -n "${CLIENT2_PID:-}" ]; then
    echo "EXIT" >&5 2>/dev/null || true
    exec 5>&- || true
    exec 6<&- || true
    if kill -0 "$CLIENT2_PID" 2>/dev/null; then
      kill "$CLIENT2_PID" 2>/dev/null
      wait "$CLIENT2_PID" 2>/dev/null
    fi
    CLIENT2_PID=""
  fi
}

# Stops the Mac listener (concurrent-file-keychain-access concern `mac-driver.sh` already
# documents), reads `-HarnessListTrust`, and prints the number of `harness-trust-record:` lines.
e15_09_trust_record_count() {
  harness_kill
  local records
  records="$(harness_list_trust)" || { e15_09_log "-HarnessListTrust exited non-zero"; echo -1; return; }
  printf '%s\n' "$records" | grep -c '^harness-trust-record: ' || true
}

# --- RAWOPEN/RAWSEND/RAWSENDPROOF/RAWREVOKE wrappers (primary client, fd 3/4) --------------------
#
# These wrap the raw pairing-candidate commands `HarnessCli.kt` adds for E15-09 (see its kdoc on
# `rawOpen`/`rawSend`/`rawSendProof`/`rawRevoke`). `e15_09_rawsend`/`e15_09_rawsendproof`/
# `e15_09_rawrevoke` each set `$LAST_SENT_PROOF_HEX` (empty for `rawrevoke`, which sends no proof)
# and `$LAST_PAIR_EVENT` to the final `EVENT PAIR_...` line (or an `ERROR ...` line if the command
# was rejected outright, e.g. no raw session open).

LAST_SENT_PROOF_HEX=""
LAST_PAIR_EVENT=""

# $1=host $2=port $3=macFingerprintBase64Url. Prints the client's raw `RAWOPEN` response line
# ("OK OPENED <cbHex>" / "OK OPENED NOCHALLENGE" / "ERROR HANDSHAKE_REJECTED <reason>" / "ERROR
# CONNECTION_CLOSED") -- callers decide what that means for their own scenario.
e15_09_rawopen() {
  e15_09_send "RAWOPEN $1 $2 $3"
  e15_09_read "$E15_09_RAWOPEN_TIMEOUT_SECONDS"
}

e15_09_rawsend() {
  e15_09_send "RAWSEND $1"
  e15_09_await_raw_send_outcome
}

e15_09_rawsendproof() {
  e15_09_send "RAWSENDPROOF $1"
  e15_09_await_raw_send_outcome
}

e15_09_await_raw_send_outcome() {
  LAST_SENT_PROOF_HEX=""
  LAST_PAIR_EVENT=""
  local line
  line="$(e15_09_read 20)" || { e15_09_log "no response to RAWSEND/RAWSENDPROOF"; LAST_PAIR_EVENT="ERROR NO_RESPONSE"; return; }
  case "$line" in
    "OK SENT "*)
      LAST_SENT_PROOF_HEX="${line#OK SENT }"
      LAST_PAIR_EVENT="$(e15_09_read 20)" || { e15_09_log "no outcome after RAWSEND/RAWSENDPROOF"; LAST_PAIR_EVENT="ERROR NO_OUTCOME"; }
      ;;
    *)
      LAST_PAIR_EVENT="$line"
      ;;
  esac
}

e15_09_rawrevoke() {
  e15_09_send "RAWREVOKE"
  LAST_SENT_PROOF_HEX=""
  LAST_PAIR_EVENT=""
  local line
  line="$(e15_09_read 20)" || { e15_09_log "no response to RAWREVOKE"; LAST_PAIR_EVENT="ERROR NO_RESPONSE"; return; }
  if [ "$line" != "OK SENT_REVOKE" ]; then
    LAST_PAIR_EVENT="$line"
    return
  fi
  LAST_PAIR_EVENT="$(e15_09_read 20)" || { e15_09_log "no outcome after RAWREVOKE"; LAST_PAIR_EVENT="ERROR NO_OUTCOME"; }
}

# Asserts the current Mac process is still alive (`kill -0 "$HARNESS_PID"`) and still listening on
# $MAC_PORT after a rejected `RAWOPEN` attempt -- distinguishes a correctly rejected handshake from a
# Mac process crash/exit, which `rawOpen`'s own `runCatching { ... }` (HarnessCli.kt) would otherwise
# make indistinguishable (both print `ERROR HANDSHAKE_REJECTED ...`). Prints a FAIL line and returns 1
# on either check failing; 0 otherwise.
e15_09_assert_mac_alive() {
  if [ -z "$HARNESS_PID" ] || ! kill -0 "$HARNESS_PID" 2>/dev/null; then
    e15_09_log "FAIL: Mac process is no longer running after the rejected RAWOPEN attempt"
    return 1
  fi
  if ! harness_wait_for_listening "$MAC_PORT" 5; then
    e15_09_log "FAIL: Mac is no longer listening on $MAC_PORT after the rejected RAWOPEN attempt"
    return 1
  fi
  e15_09_log "OK: Mac process still alive and listening after the rejected RAWOPEN attempt"
  return 0
}

# Relaunches the Mac app on the same port, without reopening a pairing window (its single-use
# window is already closed by this point in every scenario that calls this) -- used after
# `e15_09_trust_record_count` needs the listener stopped, when a scenario still needs it running
# afterward (e.g. to attempt a reconnect with an already-trusted identity).
e15_09_relaunch_plain() {
  harness_launch "$MAC_PORT"
  if ! harness_wait_for_listening "$MAC_PORT"; then
    e15_09_log "Mac listener never came back up after relaunch"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
}
