#!/usr/bin/env bash
# E03-03 spike driver: starts openssl TLS servers on the host, boots one emulator AVD headless,
# installs the spike app + androidTest APK, runs the instrumented test suite against the host
# servers (reachable from the emulator at 10.0.2.2), pulls the relevant logcat lines, and tears
# everything down. Run once per AVD; pass the AVD name as $1.
#
# Usage: scripts/run-spike.sh <avd-name> [output-dir]
set -euo pipefail

AVD_NAME="${1:?usage: run-spike.sh <avd-name> [output-dir]}"
OUT_DIR="${2:-/tmp/e0303-results/$AVD_NAME}"
SDK_DIR="/Users/miggi/Library/Android/sdk"
EMULATOR_BIN="$SDK_DIR/emulator/emulator"
ADB_BIN="$SDK_DIR/platform-tools/adb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="/tmp/e0303-certs"

MAIN_PORT=8443
TLS12_PORT=8444
EXPORTER_PORT=8445

mkdir -p "$OUT_DIR" "$CERT_DIR"

if [[ ! -f "$CERT_DIR/server.crt" ]]; then
    openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/server.key"
    openssl req -new -x509 -key "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" \
        -days 2 -subj "/CN=tandem-spike-server" -sha256
fi

EXPECTED_PIN=$(openssl x509 -in "$CERT_DIR/server.crt" -noout -pubkey \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | openssl dgst -sha256 -hex | sed 's/^.* //')
echo "expected SPKI SHA-256 pin: $EXPECTED_PIN" | tee "$OUT_DIR/pin.txt"

SERVER_PIDS=()
EMULATOR_PID=""

cleanup() {
    echo "--- cleanup ---"
    for pid in "${SERVER_PIDS[@]:-}"; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done
    if [[ -n "$EMULATOR_PID" ]]; then
        "$ADB_BIN" -s "$EMULATOR_SERIAL" emu kill 2>/dev/null || true
        wait "$EMULATOR_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

start_server() {
    local port="$1"; shift
    # openssl s_server (this build) treats a stdin EOF as an implicit quit even with -ign_eof,
    # so give it a fifo held open read-write by keepstdin.sh (never reports EOF) instead of
    # inheriting this script's already-redirected stdin.
    "$SCRIPT_DIR/keepstdin.sh" "$OUT_DIR/stdin-$port.fifo" \
        openssl s_server -accept "$port" -cert "$CERT_DIR/server.crt" -key "$CERT_DIR/server.key" \
        -naccept 200 "$@" > "$OUT_DIR/server-$port.log" 2>&1 &
    SERVER_PIDS+=("$!")
    echo "started openssl s_server on :$port (pid $!) -> $OUT_DIR/server-$port.log"
}

echo "--- starting host TLS servers ---"
start_server "$MAIN_PORT" -tls1_3 -Verify 1 -alpn tandem/1 -keymatexport "EXPORTER-Channel-Binding" -keymatexportlen 32 -state
start_server "$TLS12_PORT" -no_tls1_3 -Verify 1 -alpn tandem/1
start_server "$EXPORTER_PORT" -tls1_3 -Verify 1 -alpn tandem/1 -keymatexport "EXPORTER-Channel-Binding" -keymatexportlen 32
sleep 1

echo "--- booting $AVD_NAME headless ---"
"$EMULATOR_BIN" -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -netfast > "$OUT_DIR/emulator.log" 2>&1 &
EMULATOR_PID=$!

# Wait for the emulator to enumerate in adb, then resolve its serial.
EMULATOR_SERIAL=""
for i in $(seq 1 60); do
    EMULATOR_SERIAL=$("$ADB_BIN" devices | awk '/emulator-/{print $1; exit}')
    [[ -n "$EMULATOR_SERIAL" ]] && break
    sleep 2
done
[[ -n "$EMULATOR_SERIAL" ]] || { echo "emulator never enumerated in adb"; exit 1; }
echo "serial: $EMULATOR_SERIAL"

echo "--- waiting for boot_completed ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" wait-for-device
for i in $(seq 1 120); do
    BOOTED=$("$ADB_BIN" -s "$EMULATOR_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [[ "$BOOTED" == "1" ]] && break
    sleep 2
done
[[ "$BOOTED" == "1" ]] || { echo "emulator never finished booting"; exit 1; }
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell input keyevent 82 || true

echo "--- device security properties ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell getprop ro.build.version.release | tee "$OUT_DIR/android-version.txt"
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell getprop ro.build.version.sdk | tee "$OUT_DIR/android-sdk.txt"
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell getprop ro.hardware.keystore | tee "$OUT_DIR/keystore-hw.txt" || true
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell pm list features 2>/dev/null | grep -i strongbox | tee "$OUT_DIR/strongbox-feature.txt" || true

echo "--- building ---"
cd "$PROJECT_DIR"
JAVA_HOME=/Users/miggi/Library/Java/JavaVirtualMachines/corretto-21.0.8/Contents/Home \
    ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest 2>&1 | tee "$OUT_DIR/build.log"

APP_APK="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
TEST_APK="$PROJECT_DIR/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

echo "--- installing ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" install -r -t "$APP_APK"
"$ADB_BIN" -s "$EMULATOR_SERIAL" install -r -t "$TEST_APK"

echo "--- clearing logcat ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -c

echo "--- running instrumented tests ---"
set +e
"$ADB_BIN" -s "$EMULATOR_SERIAL" shell am instrument -w \
    -e host 10.0.2.2 \
    -e mainPort "$MAIN_PORT" \
    -e tls12Port "$TLS12_PORT" \
    -e exporterPort "$EXPORTER_PORT" \
    -e expectedPin "$EXPECTED_PIN" \
    com.tandem.spike.keystoresslsocket.test/androidx.test.runner.AndroidJUnitRunner \
    | tee "$OUT_DIR/instrument.log"
INSTRUMENT_STATUS=$?
set -e

echo "--- pulling logcat ---"
"$ADB_BIN" -s "$EMULATOR_SERIAL" logcat -d -s E0303Spike:I '*:S' | tee "$OUT_DIR/logcat.log"

echo "--- done (instrument exit=$INSTRUMENT_STATUS); results in $OUT_DIR ---"
