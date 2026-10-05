#!/usr/bin/env bash
# E70-10: end-to-end key rotation, real JVM harness client (real core/crypto, core/protocol, core/transport)
# against the real Mac server app (E15-22, `tools/harness/mac-driver.sh`, D-75 file keychain, never signed).
# One Mac build, four scenarios run in order, each from a cleared trust store and a fresh phone identity:
#
#   phone-initiated  rotationE2e_phoneInitiated_nextHandshakeUsesNewSpki -- `RAWROTATE HELDKEY` commits on
#                    the Mac (new fingerprint in its trust store); a process started with the new key's
#                    identity file then completes a handshake. rotationE2e_oldPhoneKeyAfterGraceSession_
#                    handshakeFails -- once that new-key session completed, the old key is rejected.
#   mac-initiated    rotationE2e_macInitiated_jvmClientPinsNewMacFingerprint -- the Mac begins a rotation
#                    (`-HarnessMacRotation YES`), the phone acks the verified offer, the Mac switches; after
#                    a Mac restart the phone only connects when pinning the new Mac fingerprint.
#   dropped session  the session is dropped right after `KeyRotation` (as a lost `RotationAck` does); the
#                    phone re-sends the same new key on the old key's grace session and gets the idempotent
#                    `RotationAck` (SPEC.md #idempotent-re-send, E70-08/E70-13).
#   restart in grace both processes restart between the rotation and the next session; the old key is
#                    accepted exactly once (rotationE2e_bothProcessesRestartedDuringGrace_oldKeyAcceptedOnce).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../mitm-lab/e70-09-rotation/lib/e70-09-common.sh
source "$SCRIPT_DIR/../../mitm-lab/e70-09-rotation/lib/e70-09-common.sh"
trap e15_10_teardown EXIT

FAILED=0
PORT=""
MAC_FP_B64=""
NEW_PHONE_FP_HEX=""
OLD_PHONE_FP_HEX=""

log() { e70_09_log "$*"; }

fail() {
  log "FAIL: $*"
  FAILED=1
}

# $1=scenario name $2...=extra Mac launch args. Clears the Mac trust store, starts a client with the fresh
# identity file "$1-old.bin", seeds it as paired and launches the Mac.
begin_scenario() {
  local name="$1"
  shift
  log "=== $name"
  e15_10_stop_client
  harness_kill
  harness_clear_trust || { log "-HarnessClearTrust failed"; exit 1; }
  e15_10_start_client "$name-old.bin"
  OLD_PHONE_FP_HEX="$CLIENT_SPKI_HEX"
  e15_10_seed_trust "$OLD_PHONE_FP_HEX" "E70-10 $name phone" "$E15_10_TMP_DIR/$name-seed.json"
  launch_mac "$@"
}

launch_mac() {
  e15_10_launch_plain "$PORT" "$@"
  MAC_FP_B64="$(e15_10_hex_to_b64url "$(harness_identity_spki)")"
}

relaunch_mac() {
  harness_kill
  e15_10_relaunch_plain "$PORT"
  MAC_FP_B64="$(e15_10_hex_to_b64url "$(harness_identity_spki)")"
}

# $1=identity file basename. Restarts the client process on that identity.
restart_client_as() {
  e15_10_stop_client
  e15_10_start_client "$1"
}

# $1=what. Dials the Mac pinned to $MAC_FP_B64 and passes if the session reached Ready.
expect_open() {
  local response
  response="$(e70_09_rawopen "$PORT" "${2:-$MAC_FP_B64}")"
  case "$response" in
    "OK OPENED "*) log "OK: $1" ;;
    *) fail "$1 (got: $response)" ;;
  esac
}

# $1=what. Dials the Mac and passes if the handshake was refused or the connection closed before Ready.
expect_rejected() {
  local response
  response="$(e70_09_rawopen "$PORT" "${2:-$MAC_FP_B64}")"
  case "$response" in
    "ERROR HANDSHAKE_REJECTED "* | "ERROR CONNECTION_CLOSED"*) log "OK: $1" ;;
    *) fail "$1 (got: $response)" ;;
  esac
}

close_raw() {
  e15_10_send "RAWCLOSE"
  e15_10_read 5 >/dev/null || true
}

# Generates the phone's new key and saves it as "$1-new.bin"; sets NEW_PHONE_FP_HEX.
generate_new_key() {
  local reply saved
  e15_10_send "RAWKEYGEN"
  reply="$(e15_10_read 10)" || reply=""
  NEW_PHONE_FP_HEX="${reply#OK KEYGEN }"
  e15_10_send "RAWSAVEHELDKEY $E15_10_TMP_DIR/$1-new.bin"
  saved="$(e15_10_read 10)" || saved=""
  if [ "$saved" != "OK SAVED" ] || ! printf '%s' "$NEW_PHONE_FP_HEX" | grep -Eq '^[0-9a-f]{64}$'; then
    log "FAIL: could not generate the new phone key (got: $reply / $saved)"
    exit 1
  fi
}

# $1=scenario name $2...=RAWROTATE flags. Opens a session as the current identity and rotates to the new key.
rotate_phone() {
  local name="$1"
  shift
  expect_open "$name: session opened for rotation"
  e70_09_rawrotate "$@"
}

assert_acked() {
  [ "$E70_09_ROTATE_EVENT" = "EVENT ROTATION_ACK" ] || fail "$1 (got: $E70_09_ROTATE_EVENT)"
}

assert_mac_trusts_new_phone_key() {
  if e70_09_trust_snapshot | grep -q "$NEW_PHONE_FP_HEX"; then
    log "OK: Mac trust store holds the new phone fingerprint"
  else
    fail "Mac trust store lacks the new phone fingerprint"
  fi
  relaunch_mac
}

scenario_phone_initiated() {
  begin_scenario phone
  generate_new_key phone
  rotate_phone phone HELDKEY
  assert_acked "phone: rotation was not acked"
  close_raw
  assert_mac_trusts_new_phone_key

  restart_client_as phone-new.bin
  [ "$CLIENT_SPKI_HEX" = "$NEW_PHONE_FP_HEX" ] || fail "phone: restarted client is not on the new key"
  expect_open "phone: next handshake authenticates with the new SPKI"
  close_raw

  restart_client_as phone-old.bin
  expect_rejected "phone: old key rejected after the new-key session completed"
}

scenario_mac_initiated() {
  begin_scenario mac -HarnessMacRotation YES
  local old_mac_fp_hex offer pending_fp_hex acked
  old_mac_fp_hex="$(harness_identity_spki)"
  e15_10_wait_for_log_line 'harness-mac-rotation: awaitingPhones' 20 >/dev/null || fail "mac: Mac did not begin a rotation"
  expect_open "mac: session opened"
  e15_10_send "RAWMACROTATION ACK"
  offer="$(e15_10_read "$E70_09_ROTATE_TIMEOUT_SECONDS")" || offer="EVENT NO_RESPONSE"
  case "$offer" in
    "EVENT MAC_ROTATION_OFFERED "*" VERIFIED") pending_fp_hex="$(printf '%s' "$offer" | cut -d' ' -f4)" ;;
    *) fail "mac: expected a verified offer (got: $offer)"; return ;;
  esac
  acked="$(e15_10_read 10)" || acked=""
  [ "$acked" = "OK ACKED" ] || fail "mac: offer was not acked (got: $acked)"
  e15_10_wait_for_log_line 'harness-mac-rotation-switched' 20 >/dev/null || fail "mac: Mac did not switch after the ack"
  close_raw

  relaunch_mac
  [ "$(harness_identity_spki)" = "$pending_fp_hex" ] || fail "mac: restarted Mac is not on the offered key"
  expect_open "mac: phone pinning the new Mac fingerprint connects" "$(e15_10_hex_to_b64url "$pending_fp_hex")"
  close_raw
  expect_rejected "mac: phone pinning only the old Mac fingerprint is refused" "$(e15_10_hex_to_b64url "$old_mac_fp_hex")"
}

scenario_dropped_session() {
  begin_scenario dropped
  generate_new_key dropped
  expect_open "dropped: session opened for rotation"
  e15_10_send "RAWROTATE HELDKEY NOWAIT"
  [ "$(e15_10_read "$E70_09_ROTATE_TIMEOUT_SECONDS")" = "OK SENT_ROTATION" ] || fail "dropped: KeyRotation was not sent"
  close_raw
  sleep 1
  expect_open "dropped: old key reconnects on its grace or primary pin"
  e70_09_rawrotate HELDKEY
  assert_acked "dropped: re-sent rotation was not acked"
  close_raw
  assert_mac_trusts_new_phone_key

  restart_client_as dropped-new.bin
  expect_open "dropped: new key authenticates after the recovered rotation"
}

scenario_restart_during_grace() {
  begin_scenario grace
  generate_new_key grace
  rotate_phone grace HELDKEY
  assert_acked "grace: rotation was not acked"
  close_raw
  e15_10_stop_client
  relaunch_mac

  e15_10_start_client grace-old.bin
  expect_open "grace: old key accepted once after both processes restarted"
  close_raw
  expect_rejected "grace: old key refused on the second session"
}

e15_10_setup_jvm
e15_10_setup_mac
PORT="$(e15_10_free_port)"

scenario_phone_initiated
scenario_mac_initiated
scenario_dropped_session
scenario_restart_during_grace

e15_10_assert_mac_alive "$PORT" || FAILED=1
if [ "$FAILED" -eq 0 ]; then
  log "PASS"
  exit 0
fi
exit 1
