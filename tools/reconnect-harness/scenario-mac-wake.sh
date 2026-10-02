#!/usr/bin/env bash
# Mac sleep/wake trials: sleeps the Mac, schedules a wake, then reports p95 from the phone logcat.
# Run on the Mac with the phone attached over adb.
# usage: scenario-mac-wake.sh [trials=20] [sleep-seconds=60]   (needs sudo for pmset schedule)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
trials=${1:-20} sleep_seconds=${2:-60}
out="${TANDEM_HARNESS_OUT:-$(mktemp -d)}/mac-wake.logcat"
mkdir -p "$(dirname "$out")"
adb logcat -c
for ((i = 0; i < trials; i++)); do
  wake_at="$(date -v+"$((sleep_seconds + 10))"S '+%m/%d/%y %H:%M:%S')"
  sudo pmset schedule wake "$wake_at"
  pmset sleepnow
  sleep "$((sleep_seconds + 40))"
done
adb logcat -d -v threadtime -s TandemReconnect:I >"$out"
echo "logcat: $out"
ruby "$here/run.rb" --min-trials "$trials" "$out"
