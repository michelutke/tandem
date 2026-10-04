#!/usr/bin/env bash
# tools/mitm-lab/e60-05-media-ticket/lib/e60-05-common.sh -- E60-05 shared scenario library.
#
# Reuses E15-10's lib (real Mac app via `tools/harness/mac-driver.sh`, JVM harness client over fifos,
# `-HarnessSeedTrust`). Every scenario is a media-ticket attack on the real Mac listener started with
# `-HarnessMediaTickets YES` (SPEC.md #media-ticket): the JVM client's `RAWOPEN`/`RAWTICKET` obtain a
# real ticket over a real control session and `MEDIAOPEN` presents it (or none) on a second, fully
# pinned mTLS connection. A second JVM client B (its own identity, paired too) supplies "peer B's
# client certificate". Every scenario completes mTLS first (`OK MEDIA_CONNECTED`); a pass requires the
# Mac to close the connection, print `harness-media-event: ticketRejected(<reason>)` (reason enum
# only, never ticket bytes) and print no `harness-media-event: bound`. The acceptor reports the
# five local reasons distinctly: missing, consumed, expired, revoked, peerMismatch.
set -uo pipefail

E60_05_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
E60_05_MEDIA_TIMEOUT_SECONDS=25
E60_05_TICKET=""
E60_05_MEDIA_EVENT=""
CLIENT_B_PID=""
CLIENT_B_SPKI_HEX=""

# shellcheck source=/dev/null
source "$E60_05_ROOT/tools/mitm-lab/e15-10-cert-abuse/lib/e15-10-common.sh"

e60_05_log() { echo "e60-05: $*" >&2; }

e60_05_teardown() {
  e60_05_stop_client_b 2>/dev/null || true
  e15_10_teardown
}

# Starts the second JVM client (peer B) on fds 5 (stdin) / 6 (stdout), same protocol as client A.
e60_05_start_client_b() {
  e15_10_mktmp
  local identity_file="$E15_10_TMP_DIR/client-b-identity.bin"
  mkfifo "$E15_10_TMP_DIR/client-b.in" "$E15_10_TMP_DIR/client-b.out"
  "$E15_10_JAVA_BIN" --enable-native-access=ALL-UNNAMED -cp "$E15_10_CLASSPATH" "$E15_10_JVM_MAIN_CLASS" \
    --identity-file "$identity_file" \
    <"$E15_10_TMP_DIR/client-b.in" >"$E15_10_TMP_DIR/client-b.out" 2>"$identity_file.stderr.log" &
  CLIENT_B_PID=$!
  exec 5>"$E15_10_TMP_DIR/client-b.in"
  exec 6<"$E15_10_TMP_DIR/client-b.out"
  local startup
  startup="$(e60_05_read_b "$E15_10_STARTUP_TIMEOUT_SECONDS")" || {
    e60_05_log "client B never printed its startup identity line"
    exit 1
  }
  CLIENT_B_SPKI_HEX="${startup#harness-identity-spki: }"
}

e60_05_read_b() {
  local line
  if IFS= read -r -t "$1" line <&6; then
    printf '%s\n' "$line"
    return 0
  fi
  return 1
}

e60_05_stop_client_b() {
  if [ -n "${CLIENT_B_PID:-}" ]; then
    echo "EXIT" >&5 2>/dev/null || true
    exec 5>&- || true
    exec 6<&- || true
    if kill -0 "$CLIENT_B_PID" 2>/dev/null; then
      kill "$CLIENT_B_PID" 2>/dev/null
      wait "$CLIENT_B_PID" 2>/dev/null
    fi
    CLIENT_B_PID=""
  fi
}

# Builds the JVM client and the Mac app, starts clients A and B, seeds both as paired peers and
# launches the Mac listener with the media acceptor on a free port ($PORT, $MAC_FP_B64).
e60_05_setup() {
  e15_10_setup_jvm
  e15_10_setup_mac
  e15_10_start_client "phone-a-identity.bin"
  e60_05_start_client_b
  e15_10_seed_trust "$CLIENT_SPKI_HEX" "E60-05 paired phone A" "$E15_10_TMP_DIR/seed-a.json"
  e15_10_seed_trust "$CLIENT_B_SPKI_HEX" "E60-05 paired phone B" "$E15_10_TMP_DIR/seed-b.json"
  PORT="$(e15_10_free_port)"
  e15_10_launch_plain "$PORT" -HarnessMediaTickets YES
  MAC_FP_B64="$(e15_10_hex_to_b64url "$(harness_identity_spki)")"
}

# Opens a control session as client A. Returns non-zero (and logs) if it did not open.
e60_05_open_control() {
  local response
  response="$(e15_10_rawopen 127.0.0.1 "$PORT" "$MAC_FP_B64")"
  case "$response" in
    "OK OPENED "*) return 0 ;;
    *)
      e60_05_log "FAIL: control session did not open: $response"
      return 1
      ;;
  esac
}

# Requests a ticket on A's control session; sets E60_05_TICKET (never logged).
e60_05_request_ticket() {
  e15_10_send "RAWTICKET"
  local line
  line="$(e15_10_read "$E60_05_MEDIA_TIMEOUT_SECONDS")" || line="ERROR NO_RESPONSE"
  E60_05_TICKET="${line#OK TICKET }"
  if [ "$E60_05_TICKET" = "$line" ] || ! printf '%s' "$E60_05_TICKET" | grep -Eq '^[0-9a-f]{64}$'; then
    e60_05_log "FAIL: no media ticket grant: ${line%% *} ${line#* }"
    E60_05_TICKET=""
    return 1
  fi
}

# $1=client (A|B) $2=ticketHex|NONE|SILENT [$3=HOLD]. Presents it on a new media connection; sets
# E60_05_MEDIA_EVENT to the client's final line (`EVENT MEDIA_CLOSED <ms>`, `EVENT MEDIA_OPEN`,
# `OK MEDIA_HELD`, or an `ERROR ...`). Fails unless mTLS completed first.
e60_05_media_open() {
  local client="$1" command="MEDIAOPEN 127.0.0.1 $PORT $MAC_FP_B64 $2 ${3:-}" connected
  if [ "$client" = "A" ]; then
    e15_10_send "$command"
    connected="$(e15_10_read "$E60_05_MEDIA_TIMEOUT_SECONDS")" || connected="ERROR NO_RESPONSE"
    E60_05_MEDIA_EVENT="$(e15_10_read "$E60_05_MEDIA_TIMEOUT_SECONDS")" || E60_05_MEDIA_EVENT="ERROR NO_RESPONSE"
  else
    echo "$command" >&5
    connected="$(e60_05_read_b "$E60_05_MEDIA_TIMEOUT_SECONDS")" || connected="ERROR NO_RESPONSE"
    E60_05_MEDIA_EVENT="$(e60_05_read_b "$E60_05_MEDIA_TIMEOUT_SECONDS")" || E60_05_MEDIA_EVENT="ERROR NO_RESPONSE"
  fi
  e60_05_log "MEDIAOPEN ($client): $connected / ${E60_05_MEDIA_EVENT%% *}"
  [ "$connected" = "OK MEDIA_CONNECTED" ] || { e60_05_log "FAIL: mTLS did not complete: $connected"; return 1; }
}

# $1=reason. Asserts the media connection was closed by the Mac after a completed handshake and the
# Mac logged `ticketRejected($1)`.
e60_05_assert_rejected() {
  case "$E60_05_MEDIA_EVENT" in
    "EVENT MEDIA_CLOSED "*) ;;
    *) e60_05_log "FAIL: Mac did not close the media connection: $E60_05_MEDIA_EVENT"; return 1 ;;
  esac
  if ! e15_10_wait_for_log_line "harness-media-event: ticketRejected($1)" 5 >/dev/null; then
    e60_05_log "FAIL: no ticketRejected($1) event in the Mac log"
    return 1
  fi
  e60_05_log "OK: closed after mTLS with ticketRejected($1)"
}

# $1=expected number of `harness-media-event: bound` lines (frames are only ever read after a bind).
e60_05_assert_bound_count() {
  local count
  count="$(grep -c 'harness-media-event: bound' "$HARNESS_LOG_PATH" 2>/dev/null || true)"
  if [ "${count:-0}" != "$1" ]; then
    e60_05_log "FAIL: expected $1 bound media connection(s), Mac logged ${count:-0}"
    return 1
  fi
}

# Prints OUTCOME for the scenario's expectation $1 (e.g. TICKET_REJECTED) given $FAILED.
e60_05_finish() {
  if [ "$FAILED" -eq 0 ]; then
    echo "OUTCOME: closedWithCode($1)"
  else
    echo "OUTCOME: FAILED"
  fi
}
