#!/usr/bin/env bash
# tools/mitm-lab/e73-05-manual-pairing/lib/e73-05-common.sh -- E73-05 shared scenario library.
#
# Builds on the E15-09 library (same real Mac app via `tools/harness/mac-driver.sh`, same real JVM
# harness client) and adds `e73_05_setup_manual`, which launches the Mac with a fresh *manual-mode*
# pairing window (`-HarnessOpenManualPairingWindow YES`, no QR, no secret) instead of a QR window,
# plus wrappers for the JVM client's `RAWOPENUNPINNED`/`RAWMANUAL` commands (ADR-008). Each scenario
# is self-contained and launches its own Mac process: the window is single-use.
set -uo pipefail

E73_05_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../e15-09-pairing-abuse/lib/e15-09-common.sh
source "$E73_05_LIB_DIR/../../e15-09-pairing-abuse/lib/e15-09-common.sh"

e73_05_log() { echo "e73-05: $*" >&2; }

# Like `e15_09_setup`, but opens a manual-mode window. Populates $MAC_PORT, $MAC_SPKI_HEX, $MAC_FP_B64.
e73_05_setup_manual() {
  if [ "$(uname)" != "Darwin" ]; then
    e73_05_log "this scenario requires the real macOS NWListener server -- not skipping"
    exit 1
  fi
  E15_09_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tandem-e73-05.XXXXXX")"
  e73_05_log "resolving JVM harness client runtime classpath (build once)"
  if ! E15_09_CLASSPATH="$(cd "$E15_09_ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
    e73_05_log "could not build/resolve the jvm-client runtime classpath"
    exit 1
  fi
  E15_09_CLASSPATH="${E15_09_CLASSPATH%:}"
  e73_05_log "building the real Mac app (build once)"
  if ! harness_init; then
    e73_05_log "Mac app build failed"
    exit 1
  fi
  MAC_PORT=$(( (RANDOM % 20000) + 20000 ))
  harness_launch "$MAC_PORT" -HarnessOpenManualPairingWindow YES
  if ! harness_wait_for_listening "$MAC_PORT"; then
    e73_05_log "Mac listener never came up on port $MAC_PORT"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
  MAC_SPKI_HEX="$(harness_identity_spki)"
  if [ -z "$MAC_SPKI_HEX" ]; then
    e73_05_log "no harness-identity-spki line from the Mac app"
    exit 1
  fi
  MAC_FP_B64="$(e15_09_hex_to_b64url "$MAC_SPKI_HEX")"
  if ! e15_09_wait_for_log_line 'harness-pairing-manual-window: open' >/dev/null; then
    e73_05_log "Mac app never reported its manual pairing window open"
    cat "$HARNESS_LOG_PATH" >&2
    exit 1
  fi
  e73_05_log "OK: Mac listening on $MAC_PORT, manual pairing window open"
}

# Dials the manual window without a pin; prints the client's `RAWOPEN` response line
# ("OK OPENED <cbHex>" / "ERROR HANDSHAKE_REJECTED <reason>" / ...).
e73_05_open() {
  e15_09_send "RAWOPENUNPINNED 127.0.0.1 $MAC_PORT"
  e15_09_read "$E15_09_RAWOPEN_TIMEOUT_SECONDS"
}

# Sends `RAWMANUAL $1`; sets $LAST_OK to the "OK SENT_..." line and $LAST_PAIR_EVENT to the event line.
LAST_OK=""
e73_05_manual() {
  LAST_OK=""
  LAST_PAIR_EVENT=""
  e15_09_send "RAWMANUAL $1"
  LAST_OK="$(e15_09_read 20)" || { LAST_PAIR_EVENT="ERROR NO_RESPONSE"; return; }
  case "$LAST_OK" in
    "OK SENT_"*)
      LAST_PAIR_EVENT="$(e15_09_read 30)" || LAST_PAIR_EVENT="ERROR NO_OUTCOME"
      ;;
    *)
      LAST_PAIR_EVENT="$LAST_OK"
      ;;
  esac
}

# True ($?=0) if $1 is an event meaning the Mac ended the attempt without accepting it.
e73_05_event_is_rejection() {
  case "$1" in
    "EVENT PAIR_REJECTED"*|"EVENT PAIR_CLOSED") return 0 ;;
    *) return 1 ;;
  esac
}
