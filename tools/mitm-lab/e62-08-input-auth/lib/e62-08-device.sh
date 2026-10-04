#!/usr/bin/env bash
# tools/mitm-lab/e62-08-input-auth/lib/e62-08-device.sh -- E62-08 device scenarios' library.
#
# The real phone app (debug build, accessibility remote-input service enabled, FGS running) is the
# target; the real Mac app acts as the only peer it trusts and sends the crafted input (`SENDINPUT`),
# so nothing about the phone is mocked. A physical device or emulator on adb is required; the
# operator scans the pairing QR once per scenario (the Mac harness keychain is throwaway, D-75).
# `InputCounterActivity` (tools/companion-app) stays in the foreground and logs one
# `TandemInputCounter down=<n>` line per touch that reaches it, so "injected" is measured at the
# screen, not inferred from the phone's own logs. The phone's `InputGate` drop log (`InputGate` tag,
# reason + event type only) is the second oracle.
#
# Environment: E62_08_PHONE_SERIAL (adb -s, optional when one device is attached),
# E62_08_PAIR_TIMEOUT_SECONDS (default 180), E62_08_MIRROR_TAPS (default "Start mirroring|Start now",
# the on-phone prompt button then the system MediaProjection consent button, pressed in order).
set -uo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/e62-08-common.sh"

E62_08_PAIR_TIMEOUT_SECONDS="${E62_08_PAIR_TIMEOUT_SECONDS:-180}"
E62_08_MIRROR_TAPS="${E62_08_MIRROR_TAPS:-Start mirroring|Start now}"
E62_08_COUNTER_ACTIVITY="dev.tandem.companion/.InputCounterActivity"
E62_08_SETTLE_SECONDS=3
E62_08_PHONE_FP_HEX=""
E62_08_MIRROR_SESSION_HEX=""

e62_08_adb() {
  if [ -n "${E62_08_PHONE_SERIAL:-}" ]; then
    adb -s "$E62_08_PHONE_SERIAL" "$@"
  else
    adb "$@"
  fi
}

# Builds and installs the companion app (counting activity); fails if no device is attached.
e62_08_setup_device() {
  command -v adb >/dev/null 2>&1 || { e62_08_log "adb not found on PATH"; exit 1; }
  if [ -z "$(e62_08_adb get-state 2>/dev/null)" ]; then
    e62_08_log "no adb device attached (set E62_08_PHONE_SERIAL if several are)"
    exit 1
  fi
  (cd "$E62_08_ROOT/android" && ./gradlew -q :companion-app:assembleDebug) || { e62_08_log "companion app build failed"; exit 1; }
  e62_08_adb install -r -t "$E62_08_ROOT/tools/companion-app/build/outputs/apk/debug/companion-app-debug.apk" >/dev/null \
    || { e62_08_log "companion app install failed"; exit 1; }
}

# Launches the Mac with the media acceptor and the pairing window, then waits for the operator to pair
# the phone (prints the QR URI) and for its control session to register; sets E62_08_PHONE_FP_HEX.
e62_08_pair_phone() {
  local port="$1" qr
  e62_08_launch_mac "$port" -HarnessMediaTickets YES -HarnessOpenPairingWindow YES -HarnessAutoConfirmPairing YES
  qr="$(e15_10_wait_for_log_line 'harness-pairing-qr-uri: .*' 30)" || { e62_08_log "FAIL: no pairing QR URI"; return 1; }
  e62_08_log "pair the phone now: ${qr#harness-pairing-qr-uri: }"
  local line
  line="$(e15_10_wait_for_log_line 'harness-session-registered: [0-9a-f]*' "$E62_08_PAIR_TIMEOUT_SECONDS")" \
    || { e62_08_log "FAIL: phone never connected"; return 1; }
  E62_08_PHONE_FP_HEX="${line#harness-session-registered: }"
}

# $1=label. Presses the visible on-phone control with that text (uiautomator dump, 30 s deadline).
e62_08_tap_label() {
  local deadline=$((SECONDS + 30)) point
  while (( SECONDS < deadline )); do
    e62_08_adb shell uiautomator dump /sdcard/e62-08-ui.xml >/dev/null 2>&1
    if point="$(e62_08_adb shell cat /sdcard/e62-08-ui.xml | ruby "$E62_08_ROOT/tools/mitm-lab/e62-08-input-auth/lib/ui_tap_point.rb" "$1")"; then
      # shellcheck disable=SC2086
      e62_08_adb shell input tap $point
      return 0
    fi
    sleep 1
  done
  e62_08_log "FAIL: no on-phone control labelled \"$1\""
  return 1
}

e62_08_counter_foreground() {
  e62_08_adb shell am start -n "$E62_08_COUNTER_ACTIVITY" >/dev/null
  sleep 1
}

# Starts a real mirror session the way the user does: the Mac asks, the user presses Start on the
# phone and grants the system consent; waits for the media connection to bind and sets
# E62_08_MIRROR_SESSION_HEX to the phone-minted session reference, then brings the counter forward.
e62_08_user_starts_mirror() {
  local label line labels
  e62_08_mac_command "MIRRORREQUEST $E62_08_PHONE_FP_HEX"
  IFS='|' read -ra labels <<<"$E62_08_MIRROR_TAPS"
  for label in "${labels[@]}"; do
    e62_08_tap_label "$label" || return 1
  done
  line="$(e15_10_wait_for_log_line 'harness-mirror-session: [0-9a-f]*' 60)" || { e62_08_log "FAIL: mirror never bound"; return 1; }
  E62_08_MIRROR_SESSION_HEX="${line#harness-mirror-session: }"
  e62_08_counter_foreground
}

# Ends the mirror the way the Mac window closing does (media connection cancelled).
e62_08_mirror_stops() {
  e62_08_mac_command "MIRRORSTOP"
  sleep "$E62_08_SETTLE_SECONDS"
}

# Clears logcat and starts the counter; call right before the crafted input is sent.
e62_08_begin_measure() {
  e62_08_counter_foreground
  e62_08_adb logcat -c
}

# Prints every captured `TandemInputCounter down=` logcat line (threadtime format).
e62_08_counter_lines() {
  e62_08_adb logcat -d -v threadtime -s TandemInputCounter:I | grep ' down=' || true
}

# Prints the number of touches the counter saw since `e62_08_begin_measure`.
e62_08_injected_count() {
  e62_08_counter_lines | grep -c . || true
}

# Prints the highest number of counted touches within one wall-clock second (HH:MM:SS) since the start.
e62_08_max_per_second() {
  e62_08_counter_lines | awk '{print $2}' | cut -d. -f1 | sort | uniq -c | sort -rn | awk 'NR==1{print $1}' | grep . || echo 0
}

# Prints the `input_dropped reason=... event=...` lines the phone's gate logged since the start.
e62_08_drop_lines() {
  e62_08_adb logcat -d -v brief -s InputGate:W | grep -o 'input_dropped reason=[A-Za-z]* event=[A-Z_]*' || true
}

# $1=reason $2=event. Asserts exactly one drop log entry in total and that it matches.
e62_08_assert_one_drop() {
  local drops
  drops="$(e62_08_drop_lines)"
  if [ "$drops" != "input_dropped reason=$1 event=$2" ]; then
    e62_08_log "FAIL: expected exactly one drop 'reason=$1 event=$2', phone logged: $(printf '%s' "$drops" | tr '\n' ';')"
    return 1
  fi
  e62_08_log "OK: one drop log entry (reason=$1 event=$2)"
}

# Asserts the counter saw no touch at all since `e62_08_begin_measure`.
e62_08_assert_nothing_injected() {
  local count
  count="$(e62_08_injected_count)"
  if [ "$count" != "0" ]; then
    e62_08_log "FAIL: $count touch(es) reached the foreground activity, expected none"
    return 1
  fi
  e62_08_log "OK: zero injected touches"
}

# $1=OUTCOME label. Prints the scenario outcome from $FAILED.
e62_08_finish() {
  if [ "$FAILED" -eq 0 ]; then
    echo "OUTCOME: closedWithCode($1)"
  else
    echo "OUTCOME: FAILED"
  fi
}
