#!/usr/bin/env bash
# E15-22: Mac harness driver. Builds the real Tandem.app once (Debug, CODE_SIGNING_ALLOWED=NO),
# then launches/kills/relaunches it against a throwaway on-disk file keychain
# (`-HarnessKeychainPath`, `TANDEM_HARNESS_KEYCHAIN_PASSWORD`, D-75) and drives its DEBUG-only
# trust-seeding/clearing launch hooks (`-HarnessSeedTrust`, `-HarnessClearTrust`) and listener hook
# (`-HarnessListenerPort`). Never touches the login keychain, never changes the keychain search
# list or default keychain, never signs, never rebuilds between a launch and a relaunch of the same
# keychain (a rebuilt unsigned binary is a different ACL identity -- see docs/planning/decisions.md
# D-75 and /tmp/macos-file-keychain-plan.md "Risks").
#
# Library: source this file, call `harness_init`, then any of `harness_launch`, `harness_kill`,
# `harness_seed_trust`, `harness_clear_trust`, `harness_cleanup` (E12-13, E15-15, E14-16 and
# mitm-lab consume the driver this way -- nothing else needs keychain awareness). Sourcing this
# file does not build or launch anything by itself.
#
# CLI: `tools/harness/mac-driver.sh self-test` builds once and runs the full
# launch -> lsof port check -> seed -> clear -> kill -> relaunch (no rebuild) -> same-SPKI check ->
# cleanup sequence standalone, for local/CI verification of the driver itself.
set -uo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_MACOS_DIR="$HARNESS_ROOT/macos"

# Set by harness_init; consumed by every other harness_* function.
HARNESS_TMP_DIR=""
HARNESS_KEYCHAIN_PATH=""
HARNESS_KEYCHAIN_PASSWORD=""
HARNESS_APP_BINARY=""
HARNESS_DERIVED_DATA=""
HARNESS_LOG_PATH=""
HARNESS_PID=""

harness_log() { echo "mac-driver: $*" >&2; }

# mktemp -d, a random password, and one CODE_SIGNING_ALLOWED=NO build -- the whole driver run
# (every launch/kill/relaunch below) reuses this one build and this one keychain path/password.
harness_init() {
  HARNESS_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-harness.XXXXXX")"
  HARNESS_KEYCHAIN_PATH="$HARNESS_TMP_DIR/harness.keychain-db"
  HARNESS_KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
  HARNESS_DERIVED_DATA="$HARNESS_TMP_DIR/derived-data"
  HARNESS_LOG_PATH="$HARNESS_TMP_DIR/tandem-app.log"

  harness_log "building Tandem.app (CODE_SIGNING_ALLOWED=NO, derivedDataPath $HARNESS_DERIVED_DATA)"
  if ! xcodebuild -project "$HARNESS_MACOS_DIR/Tandem.xcodeproj" -scheme Tandem \
    -destination 'platform=macOS' -derivedDataPath "$HARNESS_DERIVED_DATA" build \
    CODE_SIGNING_ALLOWED=NO -quiet; then
    harness_log "build failed"
    return 1
  fi

  HARNESS_APP_BINARY="$HARNESS_DERIVED_DATA/Build/Products/Debug/TandemApp.app/Contents/MacOS/TandemApp"
  if [ ! -x "$HARNESS_APP_BINARY" ]; then
    harness_log "built app binary not found at $HARNESS_APP_BINARY"
    return 1
  fi
}

# Launches Tandem.app in the background against the harness keychain, with its listener on $1.
# Any further arguments ($2...) are passed through as additional launch arguments (E14-16:
# `-HarnessOpenPairingWindow YES`/`-HarnessAutoConfirmPairing YES`). Sets $HARNESS_PID. Never
# rebuilds -- always the same binary `harness_init` built.
harness_launch() {
  local port="$1"
  shift
  : > "$HARNESS_LOG_PATH"
  TANDEM_HARNESS_KEYCHAIN_PASSWORD="$HARNESS_KEYCHAIN_PASSWORD" \
    "$HARNESS_APP_BINARY" \
    -HarnessKeychainPath "$HARNESS_KEYCHAIN_PATH" \
    -HarnessListenerPort "$port" \
    "$@" \
    >>"$HARNESS_LOG_PATH" 2>&1 &
  HARNESS_PID=$!
  harness_log "launched pid $HARNESS_PID on port $port ($*)"
}

# Waits (up to $2 seconds, default 10) for the harness listener to actually be accepting
# connections on $1, via lsof -- never assumes the process is ready just because it forked.
harness_wait_for_listening() {
  local port="$1"
  local timeout="${2:-10}"
  local waited=0
  while (( waited < timeout )); do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | grep -q TandemApp; then
      return 0
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  return 1
}

# Prints the `harness-identity-spki: <hex>` line's hex value from the current launch's log, or
# nothing if it hasn't appeared (yet).
harness_identity_spki() {
  grep -o 'harness-identity-spki: [0-9a-f]*' "$HARNESS_LOG_PATH" | tail -1 | awk '{print $2}'
}

# Sends SIGTERM and waits for the process to exit. No-op if nothing is running.
harness_kill() {
  if [ -n "$HARNESS_PID" ] && kill -0 "$HARNESS_PID" 2>/dev/null; then
    kill "$HARNESS_PID" 2>/dev/null
    wait "$HARNESS_PID" 2>/dev/null
  fi
  HARNESS_PID=""
}

# Runs `-HarnessSeedTrust <fixture.json>` to completion (the app exits on its own after writing)
# and returns its exit status.
harness_seed_trust() {
  local fixture_path="$1"
  TANDEM_HARNESS_KEYCHAIN_PASSWORD="$HARNESS_KEYCHAIN_PASSWORD" \
    "$HARNESS_APP_BINARY" \
    -HarnessKeychainPath "$HARNESS_KEYCHAIN_PATH" \
    -HarnessSeedTrust "$fixture_path"
}

# Runs `-HarnessClearTrust` to completion and returns its exit status.
harness_clear_trust() {
  TANDEM_HARNESS_KEYCHAIN_PASSWORD="$HARNESS_KEYCHAIN_PASSWORD" \
    "$HARNESS_APP_BINARY" \
    -HarnessKeychainPath "$HARNESS_KEYCHAIN_PATH" \
    -HarnessClearTrust YES
}

# Runs `-HarnessListTrust` to completion, printing one `harness-trust-record: <fingerprintHex>`
# line per record currently in the trust store (E14-16). Callers should stop the listener first
# (same concurrent-keychain-access concern `harness_seed_trust`/`harness_clear_trust` already
# document).
harness_list_trust() {
  TANDEM_HARNESS_KEYCHAIN_PASSWORD="$HARNESS_KEYCHAIN_PASSWORD" \
    "$HARNESS_APP_BINARY" \
    -HarnessKeychainPath "$HARNESS_KEYCHAIN_PATH" \
    -HarnessListTrust YES
}

# Kills the app if still running and deletes the temp dir (keychain file included). Always safe to
# call, including after a failed harness_init.
harness_cleanup() {
  harness_kill
  if [ -n "$HARNESS_TMP_DIR" ] && [ -d "$HARNESS_TMP_DIR" ]; then
    rm -rf "$HARNESS_TMP_DIR"
  fi
}

# Writes a minimal `-HarnessSeedTrust` fixture with a random 32-byte fingerprint to $1.
harness_write_seed_fixture() {
  local out_path="$1"
  local fingerprint_hex
  fingerprint_hex="$(openssl rand -hex 32)"
  cat > "$out_path" <<JSON
{
  "fingerprintHex": "$fingerprint_hex",
  "displayName": "mac-driver self-test peer",
  "pairedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "capabilities": []
}
JSON
}

# Full self-test: launch, confirm the port is listening, seed trust, clear trust, kill, relaunch
# (no rebuild), confirm the identity SPKI is unchanged, clean up. Exits non-zero on any failure.
harness_self_test() {
  local port=$(( (RANDOM % 20000) + 20000 ))
  local failed=0

  trap harness_cleanup EXIT

  harness_init || return 1

  harness_launch "$port"
  if ! harness_wait_for_listening "$port"; then
    harness_log "FAIL: listener never came up on port $port"
    cat "$HARNESS_LOG_PATH" >&2
    return 1
  fi
  harness_log "OK: listening on port $port"

  local spki_before
  spki_before="$(harness_identity_spki)"
  if [ -z "$spki_before" ]; then
    harness_log "FAIL: no harness-identity-spki line in log"
    failed=1
  fi

  harness_kill

  local fixture_path="$HARNESS_TMP_DIR/seed-fixture.json"
  harness_write_seed_fixture "$fixture_path"
  if ! harness_seed_trust "$fixture_path"; then
    harness_log "FAIL: -HarnessSeedTrust exited non-zero"
    failed=1
  else
    harness_log "OK: -HarnessSeedTrust exited 0"
  fi

  if ! harness_clear_trust; then
    harness_log "FAIL: -HarnessClearTrust exited non-zero"
    failed=1
  else
    harness_log "OK: -HarnessClearTrust exited 0"
  fi

  harness_launch "$port"
  if ! harness_wait_for_listening "$port"; then
    harness_log "FAIL: listener never came back up on relaunch"
    cat "$HARNESS_LOG_PATH" >&2
    failed=1
  else
    harness_log "OK: relaunch listening on port $port"
  fi

  local spki_after
  spki_after="$(harness_identity_spki)"
  if [ -z "$spki_after" ] || [ "$spki_before" != "$spki_after" ]; then
    harness_log "FAIL: identity SPKI changed across relaunch ('$spki_before' != '$spki_after')"
    failed=1
  else
    harness_log "OK: identity SPKI unchanged across relaunch ($spki_after)"
  fi

  harness_kill
  trap - EXIT
  harness_cleanup

  if [ "$failed" -ne 0 ]; then
    harness_log "self-test FAILED"
    return 1
  fi
  harness_log "self-test OK"
  return 0
}

# Only run a CLI when executed directly, never when sourced as a library.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    self-test)
      harness_self_test
      exit $?
      ;;
    *)
      echo "usage: $0 self-test" >&2
      exit 2
      ;;
  esac
fi
