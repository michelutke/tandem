#!/usr/bin/env bash
# tools/mitm-lab/e15-11-version-scenarios/lib/e15-11-common.sh -- E15-11 shared scenario library.
#
# Same self-contained-per-scenario convention as `e15-09-pairing-abuse/lib/e15-09-common.sh` and
# `e15-10-cert-abuse/lib/e15-10-common.sh`: each scenario builds and launches its own real Mac app
# (`tools/harness/mac-driver.sh`, D-75 file keychain) with no pairing window (every scenario here
# dials outside a pairing window -- these are TLS-handshake/version-negotiation attacks, not
# pairing-protocol ones), using the ephemeral P-256 cert/key helper the E15-08 self-tests already
# built (`tools/mitm-lab/selftest/lib/gen-cert.sh`/`spki-fingerprint.sh`, reused as-is: invariant 3
# means an `openssl`-generated cert whose fingerprint is seeded into `-HarnessSeedTrust` is exactly
# as "genuine" to the Mac as one a real device produced).
#
# Two scenarios (the version-mismatch Hello and the Android/ticket probe) need TLS/wire-level
# control no scripting language's TLS binding exposes (a hand-crafted app-layer `Envelope` frame; a
# server that issues real TLS 1.3 session tickets and then inspects a subsequent ClientHello's raw
# extensions) -- `lib/version_hello_client.go`/`lib/ticket_probe_server.go` (built on demand via `go
# build`, same `crypto/tls` struct-literal technique E15-10 already established) do exactly that.
#
# Source this file, call `e15_11_setup_mac`/`e15_11_setup_jvm` as needed (after
# `trap e15_11_teardown EXIT`), then use `e15_11_launch_plain`, `e15_11_seed_trust`,
# `e15_11_gen_cert`/`e15_11_spki_fingerprint_hex`, `e15_11_build_go_tools`, and (for scenario 5)
# `e15_11_start_client`/`e15_11_read`/`e15_11_send`/`e15_11_stop_client`.
set -uo pipefail

E15_11_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E15_11_ANDROID_DIR="$E15_11_LIB_ROOT/android"
E15_11_SELFTEST_LIB="$E15_11_LIB_ROOT/tools/mitm-lab/selftest/lib"
E15_11_JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
E15_11_JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.HarnessCliKt"
E15_11_TANDEM_ALPN="tandem/1"

E15_11_STARTUP_TIMEOUT_SECONDS=10
E15_11_LOG_WAIT_TIMEOUT_SECONDS=15

# shellcheck source=../../../harness/mac-driver.sh
source "$E15_11_LIB_ROOT/tools/harness/mac-driver.sh"

E15_11_TMP_DIR=""
E15_11_CLASSPATH=""
CLIENT_PID=""

e15_11_log() { echo "e15-11: $*" >&2; }

e15_11_mktmp() {
  if [ -z "$E15_11_TMP_DIR" ]; then
    E15_11_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e15-11.XXXXXX")"
  fi
}

# lowercase hex -> base64url (no padding).
e15_11_hex_to_b64url() {
  printf '%s' "$1" | xxd -r -p | base64 | tr '+/' '-_' | tr -d '=\n'
}

# Waits (up to $2 seconds, default $E15_11_LOG_WAIT_TIMEOUT_SECONDS) for a line matching regex $1
# in the current Mac launch's log; prints the last matching line and returns 0, or returns 1 on
# timeout.
e15_11_wait_for_log_line() {
  local pattern="$1"
  local timeout="${2:-$E15_11_LOG_WAIT_TIMEOUT_SECONDS}"
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

# Resolves the JVM harness client runtime classpath once (scenario 5 only -- no real Mac app is
# involved there, a scripted Go server stands in for it).
e15_11_setup_jvm() {
  e15_11_mktmp
  e15_11_log "resolving JVM harness client runtime classpath (build once)"
  if ! E15_11_CLASSPATH="$(cd "$E15_11_ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
    e15_11_log "could not build/resolve the jvm-client runtime classpath"
    exit 1
  fi
  E15_11_CLASSPATH="${E15_11_CLASSPATH%:}"
}

# Builds the real Mac app once (does not launch it).
e15_11_setup_mac() {
  e15_11_mktmp
  if [ "$(uname)" != "Darwin" ]; then
    e15_11_log "this scenario requires the real macOS NWListener server -- not skipping"
    exit 1
  fi
  e15_11_log "building the real Mac app (build once)"
  if ! harness_init; then
    e15_11_log "Mac app build failed"
    exit 1
  fi
}

# Launches the Mac app on $1 with no pairing window. Further arguments pass through to
# `harness_launch`.
e15_11_launch_plain() {
  local port="$1"
  shift
  harness_launch "$port" "$@"
  if ! harness_wait_for_listening "$port"; then
    e15_11_log "Mac listener never came up on port $port"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
}

# Writes a `-HarnessSeedTrust` fixture for a real fingerprint and seeds it (mirrors
# e15-10-common.sh's `e15_10_seed_trust`). $1=fingerprintHex $2=displayName $3=outPath.
e15_11_seed_trust() {
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
    e15_11_log "-HarnessSeedTrust failed for $display_name ($fingerprint_hex)"
    exit 1
  fi
}

e15_11_teardown() {
  e15_11_stop_client 2>/dev/null || true
  if [ -n "${E15_11_GO_SERVER_PID:-}" ] && kill -0 "$E15_11_GO_SERVER_PID" 2>/dev/null; then
    kill "$E15_11_GO_SERVER_PID" 2>/dev/null
    wait "$E15_11_GO_SERVER_PID" 2>/dev/null || true
  fi
  harness_cleanup
  if [ -n "$E15_11_TMP_DIR" ] && [ -d "$E15_11_TMP_DIR" ]; then
    for log in "$E15_11_TMP_DIR"/*.stderr.log; do
      [ -s "$log" ] && { e15_11_log "--- $log ---"; cat "$log" >&2; }
    done
    rm -rf "$E15_11_TMP_DIR"
  fi
}

# --- JVM client (scenario 5 only): fd 3 (stdin) / fd 4 (stdout+stderr) --------------------------

CLIENT_SPKI_HEX=""

e15_11_start_client() {
  e15_11_mktmp
  local identity_file="$E15_11_TMP_DIR/client-identity.bin"
  rm -f "$E15_11_TMP_DIR/client.in" "$E15_11_TMP_DIR/client.out"
  mkfifo "$E15_11_TMP_DIR/client.in" "$E15_11_TMP_DIR/client.out"
  # See e15-09-common.sh's `e15_09_start_client` comment: stderr must not share the fifo
  # `e15_11_read` reads from.
  "$E15_11_JAVA_BIN" --enable-native-access=ALL-UNNAMED -cp "$E15_11_CLASSPATH" "$E15_11_JVM_MAIN_CLASS" \
    --identity-file "$identity_file" \
    <"$E15_11_TMP_DIR/client.in" >"$E15_11_TMP_DIR/client.out" 2>"$identity_file.stderr.log" &
  CLIENT_PID=$!
  exec 3>"$E15_11_TMP_DIR/client.in"
  exec 4<"$E15_11_TMP_DIR/client.out"
  local startup
  startup="$(e15_11_read "$E15_11_STARTUP_TIMEOUT_SECONDS")" || {
    e15_11_log "client never printed its startup identity line"
    exit 1
  }
  CLIENT_SPKI_HEX="${startup#harness-identity-spki: }"
}

e15_11_read() {
  local timeout_seconds="$1"
  local line
  if IFS= read -r -t "$timeout_seconds" line <&4; then
    printf '%s\n' "$line"
    return 0
  fi
  return 1
}

e15_11_send() {
  echo "$1" >&3
}

e15_11_stop_client() {
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

# Asserts the current Mac process is still alive and still listening on $1 (mirrors
# e15-10-common.sh's `e15_10_assert_mac_alive`).
e15_11_assert_mac_alive() {
  local port="$1"
  if [ -z "$HARNESS_PID" ] || ! kill -0 "$HARNESS_PID" 2>/dev/null; then
    e15_11_log "FAIL: Mac process is no longer running after the attack attempt"
    return 1
  fi
  if ! harness_wait_for_listening "$port" 5; then
    e15_11_log "FAIL: Mac is no longer listening on $port after the attack attempt"
    return 1
  fi
  e15_11_log "OK: Mac process still alive and listening after the attack attempt"
  return 0
}

# Generates an ephemeral self-signed P-256 cert/key pair via the E15-08 self-test helper.
# $1=prefix $2=commonName. Writes ${prefix}-key.pem / ${prefix}-cert.pem.
e15_11_gen_cert() {
  "$E15_11_SELFTEST_LIB/gen-cert.sh" "$1" "$2"
}

# Prints the lowercase-hex SHA-256 SPKI fingerprint of a PEM certificate via the E15-08 self-test
# helper.
e15_11_spki_fingerprint_hex() {
  "$E15_11_SELFTEST_LIB/spki-fingerprint.sh" "$1"
}

# Prints a free TCP port via the E15-08 self-test helper.
e15_11_free_port() {
  ruby "$E15_11_SELFTEST_LIB/free-port.rb"
}

# Builds `version_hello_client.go`/`ticket_probe_server.go` once into $E15_11_TMP_DIR/bin.
# Requires `go` on PATH.
e15_11_build_go_tools() {
  e15_11_mktmp
  mkdir -p "$E15_11_TMP_DIR/bin"
  command -v go >/dev/null 2>&1 || { e15_11_log "go not found on PATH"; exit 1; }
  local lib_dir="$E15_11_LIB_ROOT/tools/mitm-lab/e15-11-version-scenarios/lib"
  if ! go build -o "$E15_11_TMP_DIR/bin/version_hello_client" "$lib_dir/version_hello_client.go"; then
    e15_11_log "failed to build version_hello_client.go"
    exit 1
  fi
  if ! go build -o "$E15_11_TMP_DIR/bin/ticket_probe_server" "$lib_dir/ticket_probe_server.go"; then
    e15_11_log "failed to build ticket_probe_server.go"
    exit 1
  fi
}

# Runs the compiled version-Hello client: $1=host $2=port $3=certPem $4=keyPem $5=major
# $6=readTimeoutMs $7=alpn (optional, defaults to $E15_11_TANDEM_ALPN; pass "none" to send no ALPN
# extension at all). Real mTLS handshake, then one hand-built CONTROL `Envelope{VersionHello{major}}`
# frame, then reads until the peer closes or the deadline elapses. Prints the tool's own stdout
# (HANDSHAKE_OK/HANDSHAKE_FAILED, SENT_ENVELOPE, and CLOSED_MS <n> / STILL_OPEN_AFTER_MS <n>).
e15_11_version_hello_client() {
  local alpn="${7:-$E15_11_TANDEM_ALPN}"
  "$E15_11_TMP_DIR/bin/version_hello_client" "$1" "$2" "$3" "$4" "$alpn" "$5" "$6"
}

# Starts the compiled ticket-probe server in the background ($1=port $2=certPem $3=keyPem), waits
# for its "LISTENING" line, and sets $E15_11_GO_SERVER_PID.
E15_11_GO_SERVER_PID=""
e15_11_start_ticket_probe_server() {
  local port="$1" cert="$2" key="$3"
  "$E15_11_TMP_DIR/bin/ticket_probe_server" "$port" "$cert" "$key" "$E15_11_TANDEM_ALPN" \
    >"$E15_11_TMP_DIR/ticket_probe_server.out" 2>"$E15_11_TMP_DIR/ticket_probe_server.err" &
  E15_11_GO_SERVER_PID=$!
  local waited=0
  while (( waited < 50 )); do
    grep -q '^LISTENING$' "$E15_11_TMP_DIR/ticket_probe_server.out" 2>/dev/null && return 0
    sleep 0.1
    waited=$((waited + 1))
  done
  e15_11_log "ticket-probe server never printed LISTENING"
  cat "$E15_11_TMP_DIR/ticket_probe_server.err" >&2
  exit 1
}
