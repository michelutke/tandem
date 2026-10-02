#!/usr/bin/env bash
# tools/mitm-lab/e15-20-preauth-dos/lib/e15-20-common.sh -- E15-20 shared scenario library.
#
# Same self-contained-per-scenario convention as E15-09/10/11: each scenario builds and launches its
# own real Mac app (`tools/harness/mac-driver.sh`, D-75 file keychain). Distinct sources are loopback
# aliases 127.0.0.2..127.0.0.9 (`e15_20_require_alias`; macOS configures only 127.0.0.1 by default, so
# a missing alias is added with `sudo -n ifconfig lo0 alias` and removed again at teardown -- if
# passwordless sudo is unavailable the scenario exits 1 with an infrastructure error, never a skip).
# Source-bound sockets come from `lib/preauth_probe.go` (built on demand via `go build`); a paired
# peer's "Ready" is observed as the Mac's first application frame after our VersionHello.
#
# SPEC.md §10 (E01-22) numbers asserted by the scenarios: TLS deadline 10 s, VersionHello deadline 5 s,
# <= 8 not-Ready connections total / <= 2 per source IP (excess closed on accept), a source with >= 10
# failed handshakes in 60 s refused for 60 s. No close code is ever written to the wire pre-auth, so
# "closed with PROTOCOL_TIMEOUT" is observed as a connection close inside the deadline window.
set -uo pipefail

E15_20_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E15_20_SELFTEST_LIB="$E15_20_LIB_ROOT/tools/mitm-lab/selftest/lib"
E15_20_LIB_DIR="$E15_20_LIB_ROOT/tools/mitm-lab/e15-20-preauth-dos/lib"

# shellcheck source=../../../harness/mac-driver.sh
source "$E15_20_LIB_ROOT/tools/harness/mac-driver.sh"

E15_20_TMP_DIR=""
E15_20_ADDED_ALIASES=""
E15_20_PROBE=""

e15_20_log() { echo "e15-20: $*" >&2; }

e15_20_mktmp() {
  if [ -z "$E15_20_TMP_DIR" ]; then
    E15_20_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e15-20.XXXXXX")"
  fi
}

e15_20_teardown() {
  harness_cleanup
  local alias_ip
  for alias_ip in $E15_20_ADDED_ALIASES; do
    sudo -n ifconfig lo0 -alias "$alias_ip" 2>/dev/null || true
  done
  if [ -n "$E15_20_TMP_DIR" ] && [ -d "$E15_20_TMP_DIR" ]; then
    rm -rf "$E15_20_TMP_DIR"
  fi
}

# Ensures loopback alias $1 (e.g. 127.0.0.2) exists; exits 1 if it can't be added.
e15_20_require_alias() {
  local alias_ip="$1"
  if ifconfig lo0 | grep -q "inet $alias_ip "; then
    return 0
  fi
  if sudo -n ifconfig lo0 alias "$alias_ip" up 2>/dev/null; then
    E15_20_ADDED_ALIASES="$E15_20_ADDED_ALIASES $alias_ip"
    return 0
  fi
  e15_20_log "loopback alias $alias_ip missing and passwordless sudo unavailable: run 'sudo ifconfig lo0 alias $alias_ip up'"
  exit 1
}

# Builds the real Mac app and the Go probe. $1 skips the Mac build when "no-mac" (scenarios that
# source e15-09-common.sh already build and launch their own Mac).
e15_20_setup() {
  e15_20_mktmp
  if [ "$(uname)" != "Darwin" ]; then
    e15_20_log "this scenario requires the real macOS NWListener server -- not skipping"
    exit 1
  fi
  command -v go >/dev/null 2>&1 || { e15_20_log "go not found on PATH"; exit 1; }
  mkdir -p "$E15_20_TMP_DIR/bin"
  if ! go build -o "$E15_20_TMP_DIR/bin/preauth_probe" "$E15_20_LIB_DIR/preauth_probe.go"; then
    e15_20_log "failed to build preauth_probe.go"
    exit 1
  fi
  E15_20_PROBE="$E15_20_TMP_DIR/bin/preauth_probe"
  if [ "${1:-}" != "no-mac" ]; then
    e15_20_log "building the real Mac app (build once)"
    harness_init || { e15_20_log "Mac app build failed"; exit 1; }
  fi
}

# Launches the Mac with no pairing window on a random port ($MAC_PORT).
MAC_PORT=""
e15_20_launch_plain() {
  MAC_PORT="$("ruby" "$E15_20_SELFTEST_LIB/free-port.rb")"
  harness_launch "$MAC_PORT"
  if ! harness_wait_for_listening "$MAC_PORT"; then
    e15_20_log "Mac listener never came up on port $MAC_PORT"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
}

# Generates a cert ($1=prefix) and prints its lowercase-hex SPKI fingerprint.
e15_20_gen_cert_fp() {
  "$E15_20_SELFTEST_LIB/gen-cert.sh" "$1" "e15-20 peer" >/dev/null
  "$E15_20_SELFTEST_LIB/spki-fingerprint.sh" "$1-cert.pem"
}

# Seeds trust for fingerprint $1 (displayName $2).
e15_20_seed_trust() {
  local fixture="$E15_20_TMP_DIR/seed-$2.json"
  cat > "$fixture" <<JSON
{
  "fingerprintHex": "$1",
  "displayName": "$2",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
  harness_seed_trust "$fixture" || { e15_20_log "-HarnessSeedTrust failed for $2"; exit 1; }
}

# Prints the last line of a probe run: $1=mode $2=srcIp then mode args. Port/host fixed.
e15_20_probe() {
  local mode="$1" src="$2"
  shift 2
  "$E15_20_PROBE" "$mode" "$src" 127.0.0.1 "$MAC_PORT" "$@"
}

# Asserts the Mac is still alive and listening.
e15_20_assert_mac_alive() {
  if [ -z "$HARNESS_PID" ] || ! kill -0 "$HARNESS_PID" 2>/dev/null; then
    e15_20_log "FAIL: Mac process is no longer running after the attack"
    return 1
  fi
  if ! harness_wait_for_listening "$MAC_PORT" 5; then
    e15_20_log "FAIL: Mac is no longer listening on $MAC_PORT after the attack"
    return 1
  fi
  return 0
}

# Runs a `ready` probe from source $1 with cert/key $2/$3; succeeds (prints READY_MS line) only if
# the peer reaches Ready within $4 ms (default 5000).
e15_20_expect_ready() {
  local out
  out="$(e15_20_probe ready "$1" "$2" "$3" "${4:-5000}")"
  e15_20_log "ready probe from $1: $out"
  case "$out" in
    READY_MS*) return 0 ;;
    *) return 1 ;;
  esac
}
