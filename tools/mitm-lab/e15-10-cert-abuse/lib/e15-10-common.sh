#!/usr/bin/env bash
# tools/mitm-lab/e15-10-cert-abuse/lib/e15-10-common.sh -- E15-10 shared scenario library.
#
# Each E15-10 scenario is self-contained (same convention as `e15-09-pairing-abuse/lib/
# e15-09-common.sh`): it builds and launches its own real Mac app (`tools/harness/mac-driver.sh`,
# D-75 file keychain) and drives it through the real JVM harness client CLI (`android/harness/
# jvm-client`, E15-15), using the `RAWOPEN` raw command E15-09 already added to `HarnessCli.kt` --
# no new raw commands are needed here: every scenario is a TLS-handshake-level attack (wrong pin,
# mismatched cert/key, revoked trust), not a pairing-protocol-level one, so the existing "dial with
# this identity, tell me if the handshake was rejected" primitive is enough.
#
# Certificate/key material for the "device" identities these scenarios pair, swap or borrow keys
# from is generated with the ephemeral self-signed P-256 helper already built for the E15-08
# self-tests (`tools/mitm-lab/selftest/lib/gen-cert.sh`/`spki-fingerprint.sh`) -- reused as-is
# rather than duplicated. Trust is bound to SPKI fingerprints only (invariant 3): the real Mac's
# `-HarnessSeedTrust` trust store does not care how a cert was generated or who (if anyone) holds
# its matching private key, so an `openssl`-generated cert whose fingerprint is seeded into that
# store is exactly as "genuine" to the Mac as one a real device produced.
#
# Source this file, call `e15_10_setup_jvm` (JVM client classpath only, cheap) and/or
# `e15_10_setup_mac` (full `xcodebuild`, only scenarios that need a real Mac app call it) after
# `trap e15_10_teardown EXIT`, then use `e15_10_start_client`/`e15_10_read`/`e15_10_send`/
# `e15_10_stop_client` (fd 3/4) and `e15_10_rawopen`.
set -uo pipefail

E15_10_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E15_10_ANDROID_DIR="$E15_10_LIB_ROOT/android"
E15_10_SELFTEST_LIB="$E15_10_LIB_ROOT/tools/mitm-lab/selftest/lib"
E15_10_JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
E15_10_JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
E15_10_TANDEM_ALPN="tandem/1"

E15_10_STARTUP_TIMEOUT_SECONDS=10
# Comfortably exceeds RAW_CHALLENGE_TIMEOUT_MS (10s, HarnessCli.kt's rawOpen) plus handshake time --
# see e15-09-common.sh's identical constant for why a shorter read timeout would lose the race.
E15_10_RAWOPEN_TIMEOUT_SECONDS=25
E15_10_LOG_WAIT_TIMEOUT_SECONDS=15

# shellcheck source=../../../harness/mac-driver.sh
source "$E15_10_LIB_ROOT/tools/harness/mac-driver.sh"

E15_10_TMP_DIR=""
E15_10_CLASSPATH=""
CLIENT_PID=""

e15_10_log() { echo "e15-10: $*" >&2; }

# base64url (no padding) -> lowercase hex.
e15_10_b64url_to_hex() {
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
e15_10_hex_to_b64url() {
  printf '%s' "$1" | xxd -r -p | base64 | tr '+/' '-_' | tr -d '=\n'
}

# Waits (up to $2 seconds, default $E15_10_LOG_WAIT_TIMEOUT_SECONDS) for a line matching regex $1
# in the current Mac launch's log; prints the last matching line and returns 0, or returns 1 on
# timeout.
e15_10_wait_for_log_line() {
  local pattern="$1"
  local timeout="${2:-$E15_10_LOG_WAIT_TIMEOUT_SECONDS}"
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

e15_10_mktmp() {
  if [ -z "$E15_10_TMP_DIR" ]; then
    E15_10_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e15-10.XXXXXX")"
  fi
}

# Resolves the JVM harness client runtime classpath once. Cheap relative to `e15_10_setup_mac` --
# scenario 2 (impostor server, no real Mac app involved) calls this alone.
e15_10_setup_jvm() {
  e15_10_mktmp
  e15_10_log "resolving JVM harness client runtime classpath (build once)"
  if ! E15_10_CLASSPATH="$(cd "$E15_10_ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
    e15_10_log "could not build/resolve the jvm-client runtime classpath"
    exit 1
  fi
  E15_10_CLASSPATH="${E15_10_CLASSPATH%:}"
}

# Builds the real Mac app once (does not launch it -- some scenarios need to seed trust records
# before the listener ever starts). Exits 1 on any build failure.
e15_10_setup_mac() {
  e15_10_mktmp
  if [ "$(uname)" != "Darwin" ]; then
    e15_10_log "this scenario requires the real macOS NWListener server -- not skipping"
    exit 1
  fi
  e15_10_log "building the real Mac app (build once)"
  if ! harness_init; then
    e15_10_log "Mac app build failed"
    exit 1
  fi
}

# Launches the Mac app on $1 with no pairing window (every E15-10 scenario dials outside a pairing
# window -- that is the whole point of a certificate-abuse scenario, as opposed to E15-09's
# pairing-candidate abuse). Any further arguments are passed through, same as `harness_launch`.
e15_10_launch_plain() {
  local port="$1"
  shift
  harness_launch "$port" "$@"
  if ! harness_wait_for_listening "$port"; then
    e15_10_log "Mac listener never came up on port $port"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
}

# Writes a `-HarnessSeedTrust` fixture for a real fingerprint (unlike `mac-driver.sh`'s own
# `harness_write_seed_fixture`, which always picks a random one) and seeds it. $1=fingerprintHex
# $2=displayName $3=outPath.
e15_10_seed_trust() {
  local fingerprint_hex="$1"
  local display_name="$2"
  local out_path="$3"
  cat > "$out_path" <<JSON
{
  "fingerprintHex": "$fingerprint_hex",
  "displayName": "$display_name",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
  if ! harness_seed_trust "$out_path"; then
    e15_10_log "-HarnessSeedTrust failed for $display_name ($fingerprint_hex)"
    exit 1
  fi
}

# Kills any running client process, the Mac app, and removes the temp dir. Safe to call multiple
# times and as an EXIT trap even if setup failed partway.
e15_10_teardown() {
  e15_10_stop_client 2>/dev/null || true
  if [ -n "$E15_10_MISMATCH_SERVER_PID" ] && kill -0 "$E15_10_MISMATCH_SERVER_PID" 2>/dev/null; then
    kill "$E15_10_MISMATCH_SERVER_PID" 2>/dev/null
    wait "$E15_10_MISMATCH_SERVER_PID" 2>/dev/null || true
  fi
  harness_cleanup
  if [ -n "$E15_10_TMP_DIR" ] && [ -d "$E15_10_TMP_DIR" ]; then
    for log in "$E15_10_TMP_DIR"/*.stderr.log; do
      [ -s "$log" ] && { e15_10_log "--- $log ---"; cat "$log" >&2; }
    done
    rm -rf "$E15_10_TMP_DIR"
  fi
}

# --- JVM client: fd 3 (stdin) / fd 4 (stdout+stderr) -------------------------------------------

CLIENT_SPKI_HEX=""

# $1=identity file basename (defaults to "client-identity.bin"; pass a fixed name to reconnect
# with the same identity across a stop/start in the same scenario, e.g. scenario 4's revoke-while-
# offline reconnect).
e15_10_start_client() {
  e15_10_mktmp
  local identity_file="$E15_10_TMP_DIR/${1:-client-identity.bin}"
  rm -f "$E15_10_TMP_DIR/client.in" "$E15_10_TMP_DIR/client.out"
  mkfifo "$E15_10_TMP_DIR/client.in" "$E15_10_TMP_DIR/client.out"
  # See e15-09-common.sh's `e15_09_start_client` comment: stderr must not share the fifo `e15_10_read`
  # reads from, and `--enable-native-access` quiets the loudest of the newer-JDK warnings at the
  # source.
  "$E15_10_JAVA_BIN" --enable-native-access=ALL-UNNAMED -cp "$E15_10_CLASSPATH" "$E15_10_JVM_MAIN_CLASS" \
    --identity-file "$identity_file" \
    <"$E15_10_TMP_DIR/client.in" >"$E15_10_TMP_DIR/client.out" 2>"$identity_file.stderr.log" &
  CLIENT_PID=$!
  exec 3>"$E15_10_TMP_DIR/client.in"
  exec 4<"$E15_10_TMP_DIR/client.out"
  local startup
  startup="$(e15_10_read "$E15_10_STARTUP_TIMEOUT_SECONDS")" || {
    e15_10_log "client never printed its startup identity line"
    exit 1
  }
  CLIENT_SPKI_HEX="${startup#harness-identity-spki: }"
}

e15_10_read() {
  local timeout_seconds="$1"
  local line
  if IFS= read -r -t "$timeout_seconds" line <&4; then
    printf '%s\n' "$line"
    return 0
  fi
  return 1
}

e15_10_send() {
  echo "$1" >&3
}

e15_10_stop_client() {
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

# $1=host $2=port $3=fingerprintBase64Url. Prints the client's raw `RAWOPEN` response line ("OK
# OPENED <cbHex>" / "OK OPENED NOCHALLENGE" / "ERROR HANDSHAKE_REJECTED <reason>" / "ERROR
# CONNECTION_CLOSED") -- see HarnessCli.kt's kdoc on `rawOpen`. Also writes the wall-clock
# milliseconds the call took to `$E15_10_TMP_DIR/rawopen.ms` -- every caller invokes this via
# `response="$(e15_10_rawopen ...)"`, which runs the function body in a command-substitution
# subshell, so a plain `E15_10_LAST_RAWOPEN_MS=...` assignment inside it never reaches the parent
# shell (confirmed: it always read back as 0, making the "<5000ms" bound check below pass
# trivially no matter how long the call actually took). Call `e15_10_load_rawopen_ms` in the parent
# right after capturing the response to populate `$E15_10_LAST_RAWOPEN_MS` for real.
e15_10_rawopen() {
  local start_ns end_ns response ms
  start_ns=$(date +%s%N)
  e15_10_send "RAWOPEN $1 $2 $3"
  response="$(e15_10_read "$E15_10_RAWOPEN_TIMEOUT_SECONDS")" || response="ERROR NO_RESPONSE"
  end_ns=$(date +%s%N)
  ms=$(( (end_ns - start_ns) / 1000000 ))
  printf '%s' "$ms" > "$E15_10_TMP_DIR/rawopen.ms"
  printf '%s\n' "$response"
}

E15_10_LAST_RAWOPEN_MS=0
e15_10_load_rawopen_ms() {
  E15_10_LAST_RAWOPEN_MS="$(cat "$E15_10_TMP_DIR/rawopen.ms" 2>/dev/null || echo 0)"
}

# Asserts the current Mac process is still alive and still listening on $1 -- distinguishes a
# correctly rejected handshake from a Mac process crash, mirroring e15-09-common.sh's
# `e15_09_assert_mac_alive`.
e15_10_assert_mac_alive() {
  local port="$1"
  if [ -z "$HARNESS_PID" ] || ! kill -0 "$HARNESS_PID" 2>/dev/null; then
    e15_10_log "FAIL: Mac process is no longer running after the rejected handshake attempt"
    return 1
  fi
  if ! harness_wait_for_listening "$port" 5; then
    e15_10_log "FAIL: Mac is no longer listening on $port after the rejected handshake attempt"
    return 1
  fi
  e15_10_log "OK: Mac process still alive and listening after the rejected handshake attempt"
  return 0
}

# Relaunches the Mac app on the same port with no pairing window -- used after
# `e15_10_trust_record_count` needs the listener stopped, when a scenario still needs it running
# afterward (scenario 4's reconnect attempt after the trust record is deleted).
e15_10_relaunch_plain() {
  local port="$1"
  harness_launch "$port"
  if ! harness_wait_for_listening "$port"; then
    e15_10_log "Mac listener never came back up after relaunch"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
}

# Stops the Mac listener (concurrent-file-keychain-access concern `mac-driver.sh` already
# documents), reads `-HarnessListTrust`, and prints the number of `harness-trust-record:` lines.
e15_10_trust_record_count() {
  harness_kill
  local records
  records="$(harness_list_trust)" || { e15_10_log "-HarnessListTrust exited non-zero"; echo -1; return; }
  printf '%s\n' "$records" | grep -c '^harness-trust-record: ' || true
}

# Generates an ephemeral self-signed P-256 cert/key pair via the E15-08 self-test helper.
# $1=prefix $2=commonName. Writes ${prefix}-key.pem / ${prefix}-cert.pem.
e15_10_gen_cert() {
  "$E15_10_SELFTEST_LIB/gen-cert.sh" "$1" "$2"
}

# Prints the lowercase-hex SHA-256 SPKI fingerprint of a PEM certificate via the E15-08 self-test
# helper.
e15_10_spki_fingerprint_hex() {
  "$E15_10_SELFTEST_LIB/spki-fingerprint.sh" "$1"
}

# Prints a free TCP port via the E15-08 self-test helper.
e15_10_free_port() {
  ruby "$E15_10_SELFTEST_LIB/free-port.rb"
}

# Connects to the real Mac's listener $1:$2 with no client certificate at all (`openssl s_client`,
# real `tandem/1` ALPN, TLS 1.3 only -- matching `ListenerFactory.swift`'s real configuration) and
# prints its genuine server certificate in PEM, extracted from the transcript. mTLS requires a
# client cert for the handshake to *complete*, but the server's own `Certificate` message is sent
# (and visible in the transcript) before it ever gets to request/validate the client's (TLS 1.3
# message order) -- the same technique `selftest/lib/pinning-client.sh` already uses. `timeout`
# guards against any hang since the handshake never completes either way. Never swallows stderr.
e15_10_capture_server_cert_pem() {
  local host="$1" port="$2"
  local transcript
  transcript="$(timeout 6 openssl s_client -connect "${host}:${port}" -tls1_3 -alpn "$E15_10_TANDEM_ALPN" </dev/null 2>&1)"
  printf '%s\n' "$transcript" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p'
}

# Builds `mismatched_cert_client.go`/`mismatched_cert_server.go` once into $E15_10_TMP_DIR/bin --
# see those files' headers for why a real `crypto/tls` `tls.Certificate{}` struct literal (built
# directly, never via `tls.X509KeyPair()` or any OpenSSL-based binding -- verified empirically that
# even a hand-rolled OpenSSL C program refuses a genuinely mismatched cert/key pair, silently
# dropping the private key instead of erroring) is what actually lets these scenarios sign a
# CertificateVerify with an unrelated key. Requires `go` on PATH.
e15_10_build_mismatch_tools() {
  e15_10_mktmp
  mkdir -p "$E15_10_TMP_DIR/bin"
  command -v go >/dev/null 2>&1 || { e15_10_log "go not found on PATH"; exit 1; }
  local lib_dir="$E15_10_LIB_ROOT/tools/mitm-lab/e15-10-cert-abuse/lib"
  if ! go build -o "$E15_10_TMP_DIR/bin/mismatched_cert_client" "$lib_dir/mismatched_cert_client.go"; then
    e15_10_log "failed to build mismatched_cert_client.go"
    exit 1
  fi
  if ! go build -o "$E15_10_TMP_DIR/bin/mismatched_cert_server" "$lib_dir/mismatched_cert_server.go"; then
    e15_10_log "failed to build mismatched_cert_server.go"
    exit 1
  fi
}

# Runs the compiled mismatched-cert client ($1=host $2=port $3=certPem $4=keyPem) -- a real TLS 1.3
# handshake presenting cert $3 while signing with the unrelated key $4. Writes the tool's own
# elapsed-ms line to `$E15_10_TMP_DIR/mismatch.ms` and prints the tool's own stdout (the caller
# greps it for `HANDSHAKE_OK`/`HANDSHAKE_FAILED`/`HANDSHAKE_TIMEOUT`). Never swallows stderr. Call
# `e15_10_load_mismatch_ms` in the parent right after capturing the output to populate
# `$E15_10_LAST_MISMATCH_MS` for real -- see `e15_10_rawopen`'s comment for why this can't just be
# a plain variable assignment inside this function.
e15_10_mismatched_cert_client() {
  local output ms
  output="$("$E15_10_TMP_DIR/bin/mismatched_cert_client" "$1" "$2" "$3" "$4" "$E15_10_TANDEM_ALPN" 2>&1)"
  ms="$(printf '%s\n' "$output" | sed -n 's/^ELAPSED_MS //p')"
  printf '%s' "${ms:-0}" > "$E15_10_TMP_DIR/mismatch.ms"
  printf '%s\n' "$output"
}

E15_10_LAST_MISMATCH_MS=0
e15_10_load_mismatch_ms() {
  E15_10_LAST_MISMATCH_MS="$(cat "$E15_10_TMP_DIR/mismatch.ms" 2>/dev/null || echo 0)"
}

# Starts the compiled mismatched-cert server in the background ($1=port $2=certPem $3=keyPem),
# waits for its "LISTENING" line, and sets `$E15_10_MISMATCH_SERVER_PID`. The caller reads its
# eventual `HANDSHAKE_OK`/`HANDSHAKE_FAILED` line and kills the process itself.
E15_10_MISMATCH_SERVER_PID=""
e15_10_start_mismatched_cert_server() {
  local port="$1" cert="$2" key="$3"
  "$E15_10_TMP_DIR/bin/mismatched_cert_server" "$port" "$cert" "$key" "$E15_10_TANDEM_ALPN" \
    >"$E15_10_TMP_DIR/mismatch_server.out" 2>"$E15_10_TMP_DIR/mismatch_server.err" &
  E15_10_MISMATCH_SERVER_PID=$!
  local waited=0
  while (( waited < 50 )); do
    grep -q '^LISTENING$' "$E15_10_TMP_DIR/mismatch_server.out" 2>/dev/null && return 0
    sleep 0.1
    waited=$((waited + 1))
  done
  e15_10_log "impostor server never printed LISTENING"
  cat "$E15_10_TMP_DIR/mismatch_server.err" >&2
  exit 1
}
