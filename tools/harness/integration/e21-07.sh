#!/usr/bin/env bash
# E21-07: the join issue's own cross-platform proof -- a real Mac identity (via the real
# TandemApp.app binary, `tools/harness/mac-driver.sh`, D-75 file keychain, never the login
# keychain, never signed) advertises a rotating id (`-HarnessPrintRotatingId`, E21-02
# `DiscoveryRotatingId`) for a CI-pinned UTC instant, and a JVM harness CLI wrapping the real
# Android `PairedMacMatcher` (E21-05, `core/discovery`) on its own fixed `Clock` recognizes (or
# rejects) it:
#
#   1. e21-07_macAt235959PhonePlus5min_recognized -- Mac pinned to 2025-06-30T23:59:59Z (one
#      second before a UTC day boundary), phone pinned to 2025-07-01T00:05:00Z (five minutes into
#      the next UTC day): recognized (the day-boundary case).
#   2. e21-07_phoneClockPlus2Days_notRecognized -- Mac pinned to 2025-06-30T23:59:59Z, phone
#      pinned to 2025-07-02T23:59:59Z (two days later): NOT recognized (outside the +/-1 day skew
#      window).
#
# Neither process's real wall clock changes and no real mDNS multicast runs -- `-HarnessPrintRotatingId`
# computes the id directly from a CI-supplied instant, and the JVM CLI's `PairedMacMatcher` runs
# against a `Clock.fixed` built from the other CI-supplied instant. Invariant 3 (CLAUDE.md):
# recognition here is a connection-candidate hint only -- this script never claims or exercises a
# trust decision; the mTLS pin check (already proven end-to-end by tools/harness/integration/e15-15.sh)
# is untouched by anything here.
set -uo pipefail

E21_07_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$E21_07_ROOT/android"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JVM_MAIN_CLASS="dev.tandem.harness.jvmclient.RotatingIdHarnessCliKt"

# shellcheck source=../mac-driver.sh
source "$E21_07_ROOT/tools/harness/mac-driver.sh"

E21_07_CLASSPATH=""
FAILED=0

log() { echo "e21-07: $*" >&2; }

cleanup() {
  harness_cleanup
}
trap cleanup EXIT

if [ "$(uname)" != "Darwin" ]; then
  log "FAIL: this integration test requires the real macOS Tandem.app -- not skipping"
  exit 1
fi

harness_init || exit 1

log "building JVM harness client runtime classpath"
if ! E21_07_CLASSPATH="$(cd "$ANDROID_DIR" && ./gradlew -q :harness:jvm-client:printRuntimeClasspath | tr '\n' ':')"; then
  log "FAIL: could not resolve :harness:jvm-client:printRuntimeClasspath"
  exit 1
fi
E21_07_CLASSPATH="${E21_07_CLASSPATH%:}"

# Runs the JVM harness CLI; prints RECOGNIZED/NOT_RECOGNIZED to stdout and exits 0/1 accordingly
# (RotatingIdHarnessCli.kt).
jvm_matches() {
  local mac_spki_fingerprint_hex="$1"
  local mac_rotating_id_hex="$2"
  local phone_instant_iso8601="$3"
  "$JAVA_BIN" -cp "$E21_07_CLASSPATH" "$JVM_MAIN_CLASS" \
    "$mac_spki_fingerprint_hex" "$mac_rotating_id_hex" "$phone_instant_iso8601"
}

# Runs `-HarnessPrintRotatingId $1`, captures the resulting mac SPKI fingerprint hex into
# $MAC_SPKI_FINGERPRINT_HEX and rotating id hex into $MAC_ROTATING_ID_HEX. Fails loudly (rather
# than leaving stale values) if either line is missing.
print_mac_rotating_id() {
  local mac_instant_iso8601="$1"
  local output
  output="$(harness_print_rotating_id "$mac_instant_iso8601")"
  MAC_SPKI_FINGERPRINT_HEX="$(echo "$output" | grep -o 'harness-identity-spki: [0-9a-f]*' | awk '{print $2}')"
  MAC_ROTATING_ID_HEX="$(echo "$output" | grep -o 'harness-rotating-id: [0-9a-f]*' | awk '{print $2}')"
  if [ -z "$MAC_SPKI_FINGERPRINT_HEX" ] || [ -z "$MAC_ROTATING_ID_HEX" ]; then
    log "FAIL: -HarnessPrintRotatingId $mac_instant_iso8601 produced no id/spki (output: $output)"
    return 1
  fi
}

test_mac_at_235959_phone_plus_5min_recognized() {
  local mac_instant="2025-06-30T23:59:59Z"
  local phone_instant="2025-07-01T00:05:00Z"

  if ! print_mac_rotating_id "$mac_instant"; then
    FAILED=1
    return
  fi
  log "mac rotating id at $mac_instant: $MAC_ROTATING_ID_HEX (spki $MAC_SPKI_FINGERPRINT_HEX)"

  local result
  result="$(jvm_matches "$MAC_SPKI_FINGERPRINT_HEX" "$MAC_ROTATING_ID_HEX" "$phone_instant")"
  if [ "$result" = "RECOGNIZED" ]; then
    log "OK: e21-07_macAt235959PhonePlus5min_recognized"
  else
    log "FAIL: e21-07_macAt235959PhonePlus5min_recognized -- expected RECOGNIZED, got $result"
    FAILED=1
  fi
}

test_phone_clock_plus_2days_not_recognized() {
  local mac_instant="2025-06-30T23:59:59Z"
  local phone_instant="2025-07-02T23:59:59Z"

  if ! print_mac_rotating_id "$mac_instant"; then
    FAILED=1
    return
  fi
  log "mac rotating id at $mac_instant: $MAC_ROTATING_ID_HEX (spki $MAC_SPKI_FINGERPRINT_HEX)"

  local result
  result="$(jvm_matches "$MAC_SPKI_FINGERPRINT_HEX" "$MAC_ROTATING_ID_HEX" "$phone_instant")"
  if [ "$result" = "NOT_RECOGNIZED" ]; then
    log "OK: e21-07_phoneClockPlus2Days_notRecognized"
  else
    log "FAIL: e21-07_phoneClockPlus2Days_notRecognized -- expected NOT_RECOGNIZED, got $result"
    FAILED=1
  fi
}

test_mac_at_235959_phone_plus_5min_recognized
test_phone_clock_plus_2days_not_recognized

if [ "$FAILED" -ne 0 ]; then
  log "FAIL: one or more e21-07 scenarios failed"
  exit 1
fi
log "OK: all e21-07 scenarios passed"
