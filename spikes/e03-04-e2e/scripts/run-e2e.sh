#!/usr/bin/env bash
# E03-04 spike driver: wires the E03-01 macOS NWListener spike and the E03-03 Android
# SSLSocket/AndroidKeyStore spike together over a real mTLS 1.3 handshake, Android emulator ->
# host macOS process (emulator reaches the host at 10.0.2.2, which resolves to the host's
# loopback interface -- so the Mac listener binding 127.0.0.1 is reachable).
#
# Usage: scripts/run-e2e.sh <avd-name> <exporter|challenge> [output-dir]
#   exporter  -- experiment 1: 10 handshakes, TLS1.3+ALPN, RFC 9266 exporter recorded both sides
#                (requires API 31+, e.g. teamorg_api34) and compared for a byte-for-byte match.
#   challenge -- experiment 2: confirms the exporter is unavailable (e.g. teamorg_api29, API<31)
#                then runs the in-band-challenge fallback and asserts the Mac listener acks it.
set -euo pipefail

AVD_NAME="${1:?usage: run-e2e.sh <avd-name> <exporter|challenge> [output-dir]}"
MODE="${2:?usage: run-e2e.sh <avd-name> <exporter|challenge> [output-dir]}"
OUT_DIR="${3:-/tmp/e0304-results/$AVD_NAME-$MODE}"
SDK_DIR="/Users/miggi/Library/Android/sdk"
EMULATOR_BIN="$SDK_DIR/emulator/emulator"
ADB_BIN="$SDK_DIR/platform-tools/adb"
JAVA_HOME_BIN="/Users/miggi/Library/Java/JavaVirtualMachines/corretto-21.0.8/Contents/Home"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_DIR="$E2E_DIR/mac"
ANDROID_DIR="$E2E_DIR/android"
WORKDIR="/tmp/e0304-workdir/$AVD_NAME-$MODE"

case "$MODE" in
  exporter) CHALLENGE_FLAG="" ;;
  challenge) CHALLENGE_FLAG="--challenge" ;;
  *) echo "unknown mode: $MODE (want exporter|challenge)"; exit 64 ;;
esac

PORT=4470
RUNS=10

rm -rf "$WORKDIR"
mkdir -p "$OUT_DIR" "$WORKDIR"

LISTENER_PID=""
EMULATOR_PID=""
EMULATOR_SERIAL=""

cleanup() {
    echo "--- cleanup ---"
    if [[ -n "$LISTENER_PID" ]]; then
        kill "$LISTENER_PID" 2>/dev/null || true
        wait "$LISTENER_PID" 2>/dev/null || true
    fi
    if [[ -n "$EMULATOR_SERIAL" ]]; then
        "$ADB_BIN" -s "$EMULATOR_SERIAL" emu kill 2>/dev/null || true
    fi
    if [[ -n "$EMULATOR_PID" ]]; then
        wait "$EMULATOR_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "--- building macOS e2e-mac (release) ---"
(cd "$MAC_DIR" && swift build -c release) 2>&1 | tee "$OUT_DIR/mac-build.log"
MAC_BIN="$MAC_DIR/.build/release/e2e-mac"

echo "--- generating macOS server identity ---"
"$MAC_BIN" setup --workdir "$WORKDIR" | tee "$OUT_DIR/mac-setup.log"
SERVER_PIN=$(cat "$WORKDIR/server.fingerprint")
echo "server pin: $SERVER_PIN"

echo "--- building Android app + androidTest ---"
(cd "$ANDROID_DIR" && JAVA_HOME="$JAVA_HOME_BIN" ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest) 2>&1 | tee "$OUT_DIR/android-build.log"
APP_APK="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
TEST_APK="$ANDROID_DIR/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

echo "--- booting $AVD_NAME headless ---"
"$EMULATOR_BIN" -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -netfast > "$OUT_DIR/emulator.log" 2>&1 &
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

"$ADB_BIN" -s "$EMULATOR_SERIAL" shell getprop ro.build.version.sdk | tee "$OUT_DIR/android-sdk.txt"

echo "--- installing ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" install -r -t "$APP_APK"
"$ADB_BIN" -s "$EMULATOR_SERIAL" install -r -t "$TEST_APK"

echo "--- phase 1: generating Android identity, capturing SPKI pin ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -c
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell am instrument -w \
    -e class com.tandem.spike.e2ehandshake.GenerateIdentityTest \
    com.tandem.spike.e2ehandshake.test/androidx.test.runner.AndroidJUnitRunner \
    | tee "$OUT_DIR/instrument-generate.log"
CLIENT_PIN=$("$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -d -s E0304Spike:I '*:S' | grep -o 'CLIENT_PIN=[0-9a-f]*' | tail -1 | cut -d= -f2)
[[ -n "$CLIENT_PIN" ]] || { echo "never captured CLIENT_PIN from logcat"; exit 1; }
echo "android client pin: $CLIENT_PIN"
printf '%s' "$CLIENT_PIN" > "$WORKDIR/android-client.fingerprint"

echo "--- starting macOS listener (mode=$MODE) ---"
"$MAC_BIN" listen --workdir "$WORKDIR" --port "$PORT" --client-name android-client \
    --exit-after "$RUNS" $CHALLENGE_FLAG > "$OUT_DIR/listener.log" 2>&1 &
LISTENER_PID=$!
sleep 1
if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
    echo "listener died immediately, see $OUT_DIR/listener.log"; cat "$OUT_DIR/listener.log"; exit 1
fi

echo "--- phase 2: running $MODE test against the Mac listener ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -c
TEST_CLASS="com.tandem.spike.e2ehandshake.ExporterHandshakeTest"
[[ "$MODE" == "challenge" ]] && TEST_CLASS="com.tandem.spike.e2ehandshake.ChallengeHandshakeTest"

set +e
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell am instrument -w \
    -e class "$TEST_CLASS" \
    -e host 10.0.2.2 \
    -e port "$PORT" \
    -e expectedServerPin "$SERVER_PIN" \
    com.tandem.spike.e2ehandshake.test/androidx.test.runner.AndroidJUnitRunner \
    | tee "$OUT_DIR/instrument-$MODE.log"
INSTRUMENT_STATUS=$?
set -e

echo "--- pulling Android logcat ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -d -s E0304Spike:I '*:S' | tee "$OUT_DIR/android-$MODE.log"

sleep 1
echo "--- done (instrument exit=$INSTRUMENT_STATUS); results in $OUT_DIR ---"

if [[ "$MODE" == "exporter" ]]; then
    echo "--- comparing exporter_sha256 values ---"
    grep -o 'exporter_sha256=[0-9a-f]*' "$OUT_DIR/listener.log" | cut -d= -f2 > "$OUT_DIR/mac-exporters.txt"
    grep -o 'exporter_sha256=[0-9a-f]*' "$OUT_DIR/android-$MODE.log" | cut -d= -f2 > "$OUT_DIR/android-exporters.txt"
    diff "$OUT_DIR/mac-exporters.txt" "$OUT_DIR/android-exporters.txt" && echo "MATCH: $(wc -l < "$OUT_DIR/mac-exporters.txt") of $RUNS pairs identical"
fi

exit "$INSTRUMENT_STATUS"
