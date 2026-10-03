#!/usr/bin/env bash
# adb Doze quick gate: force-idle for N minutes, unforce, wake screen, then report latency.
# usage: scenario-force-idle.sh [idle-minutes=10]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
minutes=${1:-10}
out="${TANDEM_HARNESS_OUT:-$(mktemp -d)}/force-idle.logcat"
mkdir -p "$(dirname "$out")"
adb logcat -c
adb shell dumpsys deviceidle force-idle
sleep "$((minutes * 60))"
adb shell dumpsys deviceidle unforce
adb shell input keyevent KEYCODE_WAKEUP
sleep 10
adb logcat -d -v threadtime -s TandemReconnect:I >"$out"
echo "logcat: $out"
ruby "$here/run.rb" "$out"
