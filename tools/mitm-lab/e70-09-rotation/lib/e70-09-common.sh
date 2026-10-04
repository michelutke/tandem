#!/usr/bin/env bash
# tools/mitm-lab/e70-09-rotation/lib/e70-09-common.sh -- E70-09 shared scenario library.
#
# Reuses E15-10's lib (real Mac app via `tools/harness/mac-driver.sh`, JVM harness client over
# fifos, `-HarnessSeedTrust`, `-HarnessListTrust`). Every scenario is a key-rotation attack on the
# real Mac listener (SPEC.md #key-rotation): `KeyRotation` where no authenticated Ready session
# exists, a `KeyRotation` whose `cb` belongs to another session, and one whose `newSpki` is another
# paired peer's key. The JVM client's `RAWKEYGEN`/`RAWCHALLENGE`/`RAWROTATE` commands (E70-09) build
# real `KeyRotation` frames over the real `RotationProof` transcript; `lib/rotation_before_hello_
# client.go` sends one before `VersionHello`. A scenario passes only if the connection was closed
# or answered with `RotationReject` for the expected reason AND the Mac's trust store (record count
# and fingerprints, `-HarnessListTrust`) is identical before and after.
set -uo pipefail

E70_09_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E70_09_ROTATE_TIMEOUT_SECONDS=25

# shellcheck source=/dev/null
source "$E70_09_ROOT/tools/mitm-lab/e15-10-cert-abuse/lib/e15-10-common.sh"

E70_09_ROTATE_EVENT=""

e70_09_log() { echo "e70-09: $*" >&2; }

# Stops the Mac listener and prints the sorted `harness-trust-record:` lines (every record's
# fingerprint). Callable before the first launch too (nothing to stop).
e70_09_trust_snapshot() {
  harness_kill
  harness_list_trust | grep '^harness-trust-record: ' | sort
}

# $1=snapshot taken before the attack. Fails (and logs both) unless the trust store is unchanged.
e70_09_assert_trust_unchanged() {
  local before="$1" after
  after="$(e70_09_trust_snapshot)"
  if [ "$before" != "$after" ]; then
    e70_09_log "FAIL: trust store changed"
    e70_09_log "before: $(printf '%s' "$before" | tr '\n' ' ')"
    e70_09_log "after:  $(printf '%s' "$after" | tr '\n' ' ')"
    return 1
  fi
  e70_09_log "OK: trust store unchanged ($(printf '%s\n' "$after" | grep -c . || true) record(s), same fingerprints)"
}

# $1=port $2=macFingerprintBase64Url. Opens the raw session with CONNECT-equivalent trusted identity
# and prints the RAWOPEN response line.
e70_09_rawopen() {
  e15_10_rawopen 127.0.0.1 "$1" "$2"
}

# $@=RAWROTATE flags. Sets E70_09_ROTATE_EVENT to the client's `EVENT ROTATION_*` line
# (`ERROR ...` when the client refused to send).
e70_09_rawrotate() {
  e15_10_send "RAWROTATE $*"
  local sent
  sent="$(e15_10_read "$E70_09_ROTATE_TIMEOUT_SECONDS")" || sent="ERROR NO_RESPONSE"
  case "$sent" in
    "OK SENT_ROTATION")
      E70_09_ROTATE_EVENT="$(e15_10_read "$E70_09_ROTATE_TIMEOUT_SECONDS")" || E70_09_ROTATE_EVENT="EVENT ROTATION_TIMEOUT"
      ;;
    *) E70_09_ROTATE_EVENT="$sent" ;;
  esac
  e70_09_log "RAWROTATE $*: $E70_09_ROTATE_EVENT"
}

# Prints the Mac's RotationChallenge hex for the current raw session ("" if none).
e70_09_rawchallenge() {
  e15_10_send "RAWCHALLENGE"
  local line
  line="$(e15_10_read "$E70_09_ROTATE_TIMEOUT_SECONDS")" || line=""
  printf '%s' "${line#OK CHALLENGE }" | grep -E '^[0-9a-f]{64}$' || true
}

# Builds `rotation_before_hello_client.go` once into $E15_10_TMP_DIR/bin.
e70_09_build_go_tool() {
  e15_10_mktmp
  mkdir -p "$E15_10_TMP_DIR/bin"
  command -v go >/dev/null 2>&1 || { e70_09_log "go not found on PATH"; exit 1; }
  if ! go build -o "$E15_10_TMP_DIR/bin/rotation_before_hello_client" \
    "$E70_09_ROOT/tools/mitm-lab/e70-09-rotation/lib/rotation_before_hello_client.go"; then
    e70_09_log "failed to build rotation_before_hello_client.go"
    exit 1
  fi
}

# $1=host $2=port $3=certPem $4=keyPem $5=readTimeoutMs. Prints the tool's stdout.
e70_09_rotation_before_hello_client() {
  "$E15_10_TMP_DIR/bin/rotation_before_hello_client" "$1" "$2" "$3" "$4" "$E15_10_TANDEM_ALPN" "$5" 2>&1
}
