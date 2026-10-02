#!/usr/bin/env bash
# Phone Wi-Fi switch trials: alternates the phone between two networks via adb, then reports p95.
# usage: scenario-wifi-switch.sh <ssid-a> <pass-a> <ssid-b> <pass-b> [trials=20] [settle-seconds=15]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ssid_a=$1 pass_a=$2 ssid_b=$3 pass_b=$4 trials=${5:-20} settle=${6:-15}
out="${TANDEM_HARNESS_OUT:-$(mktemp -d)}/wifi-switch.logcat"
mkdir -p "$(dirname "$out")"
adb logcat -c
for ((i = 0; i < trials; i++)); do
  if ((i % 2 == 0)); then ssid=$ssid_b pass=$pass_b; else ssid=$ssid_a pass=$pass_a; fi
  adb shell cmd wifi connect-network "$ssid" wpa2 "$pass"
  sleep "$settle"
done
adb logcat -d -v threadtime -s TandemReconnect:I >"$out"
echo "logcat: $out"
ruby "$here/run.rb" --min-trials "$trials" "$out"
