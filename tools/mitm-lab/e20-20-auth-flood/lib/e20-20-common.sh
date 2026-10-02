#!/usr/bin/env bash
# tools/mitm-lab/e20-20-auth-flood/lib/e20-20-common.sh -- E20-20 shared scenario library.
#
# Reuses E15-10's lib (real Mac app via `tools/harness/mac-driver.sh`, JVM harness client over
# fifos, `-HarnessSeedTrust`). The attacker is an already-paired phone: its identity is seeded into
# the Mac's trust store, it completes the real handshake (CONNECT), then floods CONTROL with the
# harness `FLOOD HEARTBEAT|CONTROL <perSecond> <seconds>` command. `LIMIT_EXCEEDED` has no wire
# signal (SPEC.md #errors-and-close-codes), so a close is observed as the client session no longer
# being Ready once the flood ends. The Mac's trust store is read back with `-HarnessListTrust`.
set -uo pipefail

E20_20_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E20_20_CONNECT_TIMEOUT_SECONDS=10
E20_20_FLOOD_SLACK_SECONDS=30

# shellcheck source=/dev/null
source "$E20_20_ROOT/tools/mitm-lab/e15-10-cert-abuse/lib/e15-10-common.sh"

E20_20_FLOOD_LINE=""
export E20_20_TRUST_COUNT_AFTER=""

e20_20_log() { echo "e20-20: $*" >&2; }

# $1=HEARTBEAT|CONTROL $2=perSecond $3=seconds. Seeds the client's identity, connects, floods, then
# fills E20_20_FLOOD_LINE (the client's `OK FLOOD ...` line) and E20_20_TRUST_COUNT_AFTER (stops
# the Mac). Returns non-zero only on an infrastructure failure, never on a "wrong" attack outcome.
e20_20_flood_and_report() {
  local kind="$1" per_second="$2" seconds="$3"
  e15_10_setup_jvm
  e15_10_setup_mac
  e15_10_start_client "phone-identity.bin"
  e15_10_seed_trust "$CLIENT_SPKI_HEX" "E20-20 paired phone" "$E15_10_TMP_DIR/seed-phone.json"

  local port
  port="$(e15_10_free_port)"
  e15_10_launch_plain "$port"
  local mac_fp_b64
  mac_fp_b64="$(e15_10_hex_to_b64url "$(harness_identity_spki)")"

  e15_10_send "CONNECT 127.0.0.1 $port $mac_fp_b64"
  local connect_response
  connect_response="$(e15_10_read "$E20_20_CONNECT_TIMEOUT_SECONDS")" || connect_response="ERROR NO_RESPONSE"
  if [ "$connect_response" != "OK CONNECTED" ]; then
    e20_20_log "FAIL: authenticated CONNECT did not reach Ready: $connect_response"
    return 1
  fi

  e15_10_send "FLOOD $kind $per_second $seconds"
  E20_20_FLOOD_LINE="$(e15_10_read $((seconds + E20_20_FLOOD_SLACK_SECONDS)))" || E20_20_FLOOD_LINE="ERROR NO_RESPONSE"
  e20_20_log "flood $kind ${per_second}/s for ${seconds}s: $E20_20_FLOOD_LINE"
  case "$E20_20_FLOOD_LINE" in
    "OK FLOOD "*) ;;
    *) return 1 ;;
  esac

  e15_10_assert_mac_alive "$port" || return 1
  E20_20_TRUST_COUNT_AFTER="$(e15_10_trust_record_count)"
}

# True when the flood ended with the client session no longer Ready (the Mac closed it).
e20_20_closed_with_limit_exceeded() {
  case "$E20_20_FLOOD_LINE" in
    *"STATE=Ready"*) return 1 ;;
    "OK FLOOD "*) return 0 ;;
    *) return 1 ;;
  esac
}
