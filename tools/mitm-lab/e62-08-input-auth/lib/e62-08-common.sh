#!/usr/bin/env bash
# tools/mitm-lab/e62-08-input-auth/lib/e62-08-common.sh -- E62-08 shared library.
#
# Input authorization (invariant 8): the real Mac app's DEBUG-only `SENDINPUT` stdin command
# (`-HarnessInteractiveCommands YES`, `HarnessStatusRingCommands.swift`) sends crafted `InputEvent`s
# on the INPUT channel with no mirror session, a stale or foreign session reference, a flood or
# out-of-range coordinates -- input the real mirror window never produces. Reuses E15-10's lib (real
# Mac app via `tools/harness/mac-driver.sh`, JVM harness client over fifos, `-HarnessSeedTrust`).
#
# Two consumers: `tools/harness/integration/e62-08.sh` (the E15-15 harness: the JVM client's
# `INPUTWATCH` runs the real `InputGate` with a recording dispatcher) and the device scenarios in
# `scenarios/` (the real phone app with the companion `InputCounterActivity` in the foreground).
set -uo pipefail

E62_08_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E62_08_CANARY_PREFIX="TANDEM-CANARY-"
E62_08_STATS_TIMEOUT_SECONDS=15
E62_08_MAC_FIFO=""

# shellcheck source=/dev/null
source "$E62_08_ROOT/tools/mitm-lab/e15-10-cert-abuse/lib/e15-10-common.sh"

e62_08_log() { echo "e62-08: $*" >&2; }

# Fresh canary nonce, e.g. TANDEM-CANARY-1f3a....
e62_08_new_canary() {
  printf '%s%s' "$E62_08_CANARY_PREFIX" "$(openssl rand -hex 8)"
}

# $1=port. Launches the real Mac app with the interactive command loop on a fifo wired to fd 6
# (same dance as `tools/harness/integration/e23-08.sh`'s `launch_mac_interactive`), plus any further
# launch arguments.
e62_08_launch_mac() {
  local port="$1"
  shift
  E62_08_MAC_FIFO="$HARNESS_TMP_DIR/mac-stdin.fifo"
  rm -f "$E62_08_MAC_FIFO"
  mkfifo "$E62_08_MAC_FIFO"
  : > "$HARNESS_LOG_PATH"
  TANDEM_HARNESS_KEYCHAIN_PASSWORD="$HARNESS_KEYCHAIN_PASSWORD" \
    "$HARNESS_APP_BINARY" \
    -HarnessKeychainPath "$HARNESS_KEYCHAIN_PATH" \
    -HarnessListenerPort "$port" \
    -HarnessInteractiveCommands YES \
    "$@" \
    <"$E62_08_MAC_FIFO" >>"$HARNESS_LOG_PATH" 2>&1 &
  HARNESS_PID=$!
  exec 6>"$E62_08_MAC_FIFO"
  if ! harness_wait_for_listening "$port"; then
    e62_08_log "Mac listener never came up on port $port"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
}

e62_08_mac_command() {
  printf '%s\n' "$1" >&6
}

# $1=peerFingerprintHex $2=TAP|TAPOUT|SETTEXT $3=count $4=perSecond $5=NONE|RANDOM|sessionIdHex [$6=text].
# Sends the crafted events and waits for the Mac's `OK SENT_INPUT <count>` acknowledgement.
e62_08_send_input() {
  local before after
  before="$(grep -c '^OK SENT_INPUT' "$HARNESS_LOG_PATH" 2>/dev/null || true)"
  e62_08_mac_command "SENDINPUT $*"
  local waited=0 timeout=$(( ${3:-1} / ${4:-1} + 20 ))
  while (( waited < timeout * 10 )); do
    after="$(grep -c '^OK SENT_INPUT' "$HARNESS_LOG_PATH" 2>/dev/null || true)"
    [ "${after:-0}" -gt "${before:-0}" ] && return 0
    if grep -q '^ERROR ' "$HARNESS_LOG_PATH" 2>/dev/null; then
      e62_08_log "FAIL: Mac refused SENDINPUT: $(grep '^ERROR ' "$HARNESS_LOG_PATH" | tail -1)"
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  e62_08_log "FAIL: Mac never acknowledged SENDINPUT $2 $3"
  return 1
}

# $1=canary $2..=capture files (non-empty). Runs log-audit (E15-17) over them as `--logcat` /
# `--unified-log` inputs; returns non-zero if the canary occurs in any of them.
e62_08_log_audit() {
  local canary="$1" logcat="$2" unified="${3:-}"
  local args=(--canary "$canary" --logcat "$logcat")
  [ -n "$unified" ] && args+=(--unified-log "$unified")
  "$E62_08_ROOT/tools/log-audit/log-audit.sh" "${args[@]}"
}
