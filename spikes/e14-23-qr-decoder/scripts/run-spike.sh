#!/usr/bin/env bash
# E14-23 spike driver: boots one emulator AVD headless (with a full packet capture running),
# installs both the ML Kit and zxing-cpp spike apps + their androidTest APKs, runs each
# instrumented suite (correctness + 20-run decode timing), captures per-UID network byte
# counters (dumpsys netstats) before the run, immediately after, and after a further 60 s idle
# window, pulls the relevant logcat lines, then tears everything down.
#
# Usage: scripts/run-spike.sh [avd-name] [output-dir]
set -euo pipefail

AVD_NAME="${1:-teamorg_api34}"
OUT_DIR="${2:-/tmp/e1423-results}"
SDK_DIR="/Users/miggi/Library/Android/sdk"
EMULATOR_BIN="$SDK_DIR/emulator/emulator"
ADB_BIN="$SDK_DIR/platform-tools/adb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IDLE_SECONDS=60

MLKIT_PKG="com.tandem.spike.qrdecoder.mlkit"
ZXING_PKG="com.tandem.spike.qrdecoder.zxing"

mkdir -p "$OUT_DIR"

EMULATOR_PID=""
EMULATOR_SERIAL=""

cleanup() {
    echo "--- cleanup ---"
    if [[ -n "$EMULATOR_SERIAL" ]]; then
        "$ADB_BIN" -s "$EMULATOR_SERIAL" emu kill 2>/dev/null || true
    fi
    if [[ -n "$EMULATOR_PID" ]]; then
        wait "$EMULATOR_PID" 2>/dev/null || true
    fi
    if [[ -n "$(jobs -p)" ]]; then
        kill $(jobs -p) 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "--- booting $AVD_NAME headless (with tcpdump capture) ---"
"$EMULATOR_BIN" -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -netfast \
    -tcpdump "$OUT_DIR/capture.pcap" > "$OUT_DIR/emulator.log" 2>&1 &
EMULATOR_PID=$!

for i in $(seq 1 60); do
    EMULATOR_SERIAL=$("$ADB_BIN" devices | awk '/emulator-/{print $1; exit}')
    [[ -n "$EMULATOR_SERIAL" ]] && break
    sleep 2
done
[[ -n "$EMULATOR_SERIAL" ]] || { echo "emulator never enumerated in adb"; exit 1; }
echo "serial: $EMULATOR_SERIAL"

"$ADB_BIN" -s "$EMULATOR_SERIAL" wait-for-device
for i in $(seq 1 120); do
    BOOTED=$("$ADB_BIN" -s "$EMULATOR_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [[ "$BOOTED" == "1" ]] && break
    sleep 2
done
[[ "$BOOTED" == "1" ]] || { echo "emulator never finished booting"; exit 1; }
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell input keyevent 82 || true

echo "--- building ---"
cd "$PROJECT_DIR"
JAVA_HOME=/Users/miggi/Library/Java/JavaVirtualMachines/corretto-21.0.8/Contents/Home \
    ./gradlew :app-mlkit:assembleDebug :app-mlkit:assembleDebugAndroidTest \
              :app-zxing:assembleDebug :app-zxing:assembleDebugAndroidTest \
    2>&1 | tee "$OUT_DIR/build.log"

run_decoder() {
    local name="$1" pkg="$2" apk="$3" testApk="$4" runner="$5"

    echo "=== $name ==="
    "$ADB_BIN" -s "$EMULATOR_SERIAL" uninstall "$pkg" >/dev/null 2>&1 || true
    "$ADB_BIN" -s "$EMULATOR_SERIAL" uninstall "$pkg.test" >/dev/null 2>&1 || true
    "$ADB_BIN" -s "$EMULATOR_SERIAL" install -r -t "$apk"
    "$ADB_BIN" -s "$EMULATOR_SERIAL" install -r -t "$testApk"

    local uid
    uid=$("$ADB_BIN" -s "$EMULATOR_SERIAL" shell pm list packages -U | grep "^package:$pkg " | sed 's/.*uid://' | tr -d '\r ')
    echo "uid=$uid" | tee "$OUT_DIR/$name-uid.txt"

    "$ADB_BIN" -s "$EMULATOR_SERIAL" shell dumpsys netstats detail > "$OUT_DIR/$name-netstats-before.txt" 2>&1 || true
    "$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -c

    echo "--- running instrumented tests: $name ---"
    set +e
    "$ADB_BIN" -s "$EMULATOR_SERIAL" shell am instrument -w "$pkg.test/$runner" \
        | tee "$OUT_DIR/$name-instrument.log"
    set -e

    echo "--- idle window: ${IDLE_SECONDS}s ---"
    sleep "$IDLE_SECONDS"

    "$ADB_BIN" -s "$EMULATOR_SERIAL" shell dumpsys netstats detail > "$OUT_DIR/$name-netstats-after.txt" 2>&1 || true
    "$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -d -s E1423Spike:I '*:S' > "$OUT_DIR/$name-logcat.log"

    echo "netstats for uid=$uid (before vs. after decode+idle):"
    python3 "$SCRIPT_DIR/netstats-bytes.py" "$uid" "$OUT_DIR/$name-netstats-before.txt" | tee "$OUT_DIR/$name-netstats-before-uid.txt"
    python3 "$SCRIPT_DIR/netstats-bytes.py" "$uid" "$OUT_DIR/$name-netstats-after.txt" | tee "$OUT_DIR/$name-netstats-after-uid.txt"
}

run_decoder "mlkit" "$MLKIT_PKG" \
    "$PROJECT_DIR/app-mlkit/build/outputs/apk/debug/app-mlkit-debug.apk" \
    "$PROJECT_DIR/app-mlkit/build/outputs/apk/androidTest/debug/app-mlkit-debug-androidTest.apk" \
    "androidx.test.runner.AndroidJUnitRunner"

run_decoder "zxing" "$ZXING_PKG" \
    "$PROJECT_DIR/app-zxing/build/outputs/apk/debug/app-zxing-debug.apk" \
    "$PROJECT_DIR/app-zxing/build/outputs/apk/androidTest/debug/app-zxing-debug-androidTest.apk" \
    "androidx.test.runner.AndroidJUnitRunner"

echo "--- stopping tcpdump capture (emu kill will flush it) ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" emu kill 2>/dev/null || true
wait "$EMULATOR_PID" 2>/dev/null || true
EMULATOR_PID=""
EMULATOR_SERIAL=""

if [[ -f "$OUT_DIR/capture.pcap" ]]; then
    echo "--- scanning capture.pcap for google/firebase telemetry hostnames ---"
    strings "$OUT_DIR/capture.pcap" | grep -iE "googleapis|firebaselogging|google\.com|gstatic|doubleclick" | sort -u \
        | tee "$OUT_DIR/capture-hostnames.txt" || echo "(no matching strings found)" | tee "$OUT_DIR/capture-hostnames.txt"
fi

echo "--- done; results in $OUT_DIR ---"
