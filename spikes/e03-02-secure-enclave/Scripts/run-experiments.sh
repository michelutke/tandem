#!/usr/bin/env bash
# Drives the E03-02 acceptance-criteria experiments: SE key generation feasibility (entitlement
# probing) plus a 20-run handshake-latency baseline for whichever key backing actually works.
# Results land in Scripts/../results/ next to a machine-readable summary.txt that
# docs/spikes/secure-enclave-identity.md quotes from.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN=.build/debug/se-identity-spike
OPENSSL=$(command -v /opt/homebrew/bin/openssl 2>/dev/null || command -v openssl)
WORK=$(mktemp -d /tmp/se-spike-experiment.XXXXXX)
RESULTS="$(pwd)/results"
rm -rf "$RESULTS"
mkdir -p "$RESULTS"

echo "openssl: $OPENSSL ($($OPENSSL version))" | tee "$RESULTS/summary.txt"
echo "hardware: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)" | tee -a "$RESULTS/summary.txt"
swift build -c debug 2>&1 | tail -5
codesign -dv "$BIN" 2>&1 | tee "$RESULTS/binary-signature.log"

section() { echo; echo "=== $1 ===" | tee -a "$RESULTS/summary.txt"; }

########################################################################
section "1. SE key generation, unsigned/ad-hoc swift build binary, data-protection keychain"
"$BIN" keygen --label se-spike-exp-se-dpk --backing se --persistent true > "$RESULTS/keygen-se-dpk.log" 2>&1
echo "exit=$?" >> "$RESULTS/keygen-se-dpk.log"
"$BIN" cleanup --label se-spike-exp-se-dpk >> "$RESULTS/keygen-se-dpk.log" 2>&1
grep -q "^keygen:" "$RESULTS/keygen-se-dpk.log" && echo "SE keygen (ad-hoc, data-protection keychain): OK" | tee -a "$RESULTS/summary.txt" \
  || echo "SE keygen (ad-hoc, data-protection keychain): FAILED -- $(grep '^ERROR' "$RESULTS/keygen-se-dpk.log")" | tee -a "$RESULTS/summary.txt"

section "2. SW key generation, unsigned/ad-hoc swift build binary, data-protection keychain"
"$BIN" keygen --label se-spike-exp-sw-dpk --backing sw --persistent true > "$RESULTS/keygen-sw-dpk.log" 2>&1
echo "exit=$?" >> "$RESULTS/keygen-sw-dpk.log"
"$BIN" cleanup --label se-spike-exp-sw-dpk >> "$RESULTS/keygen-sw-dpk.log" 2>&1
grep -q "^keygen:" "$RESULTS/keygen-sw-dpk.log" && echo "SW keygen (ad-hoc, data-protection keychain): OK" | tee -a "$RESULTS/summary.txt" \
  || echo "SW keygen (ad-hoc, data-protection keychain): FAILED -- $(grep '^ERROR' "$RESULTS/keygen-sw-dpk.log")" | tee -a "$RESULTS/summary.txt"

section "3. SE key generation, unsigned/ad-hoc swift build binary, legacy (login) keychain"
"$BIN" keygen --label se-spike-exp-se-legacy --backing se --persistent true --legacy-keychain > "$RESULTS/keygen-se-legacy.log" 2>&1
echo "exit=$?" >> "$RESULTS/keygen-se-legacy.log"
"$BIN" cleanup --label se-spike-exp-se-legacy >> "$RESULTS/keygen-se-legacy.log" 2>&1
grep -q "^keygen:" "$RESULTS/keygen-se-legacy.log" && echo "SE keygen (ad-hoc, legacy keychain): OK" | tee -a "$RESULTS/summary.txt" \
  || echo "SE keygen (ad-hoc, legacy keychain): FAILED -- $(grep '^ERROR' "$RESULTS/keygen-se-legacy.log")" | tee -a "$RESULTS/summary.txt"

section "4. SW key generation, unsigned/ad-hoc swift build binary, legacy (login) keychain"
"$BIN" keygen --label se-spike-exp-sw-legacy --backing sw --persistent true --legacy-keychain > "$RESULTS/keygen-sw-legacy.log" 2>&1
echo "exit=$?" >> "$RESULTS/keygen-sw-legacy.log"
grep -q "^keygen:" "$RESULTS/keygen-sw-legacy.log" && echo "SW keygen (ad-hoc, legacy keychain): OK" | tee -a "$RESULTS/summary.txt" \
  || echo "SW keygen (ad-hoc, legacy keychain): FAILED -- $(grep '^ERROR' "$RESULTS/keygen-sw-legacy.log")" | tee -a "$RESULTS/summary.txt"

section "5. Export-test: attempt private key export (SW should succeed, SE should fail if it ever keygens)"
"$BIN" export-test --backing sw --label se-spike-exp-export-sw > "$RESULTS/export-sw.log" 2>&1
cat "$RESULTS/export-sw.log" | tee -a "$RESULTS/summary.txt"

section "6. Relaunch check: software identity from section 4 survives a fresh process"
"$BIN" relaunch-check --label se-spike-exp-sw-legacy > "$RESULTS/relaunch-sw-legacy.log" 2>&1
cat "$RESULTS/relaunch-sw-legacy.log" | tee -a "$RESULTS/summary.txt"

section "7. 20-run handshake latency baseline: software P-256 identity (legacy keychain) as NWListener local identity, openssl s_client peer"
PORT=4610
"$BIN" listen --backing sw --label se-spike-exp-latency --legacy-keychain --port $PORT --exit-after 20 > "$RESULTS/listener-sw-latency.log" 2>&1 &
LISTENER_PID=$!
for _ in $(seq 1 50); do
  grep -q "listener-state.*state=ready" "$RESULTS/listener-sw-latency.log" 2>/dev/null && break
  sleep 0.1
done

CLIENT_CERT_DIR="$WORK/openssl-client"
mkdir -p "$CLIENT_CERT_DIR"
"$OPENSSL" ecparam -genkey -name prime256v1 -noout -out "$CLIENT_CERT_DIR/client-key.pem"
"$OPENSSL" req -new -x509 -key "$CLIENT_CERT_DIR/client-key.pem" -out "$CLIENT_CERT_DIR/client-cert.pem" -days 2 -subj "/CN=se-spike-openssl-client" -sha256

OK=0
for i in $(seq 1 20); do
  START=$(python3 -c 'import time; print(time.time_ns())')
  echo -e "hello\n" | "$OPENSSL" s_client -connect 127.0.0.1:$PORT -tls1_3 -cert "$CLIENT_CERT_DIR/client-cert.pem" -key "$CLIENT_CERT_DIR/client-key.pem" -quiet > "$RESULTS/osslclient-sw-$i.log" 2>&1
  END=$(python3 -c 'import time; print(time.time_ns())')
  ELAPSED_MS=$(( (END - START) / 1000000 ))
  echo "client_wall_ms run=$i elapsed_ms=$ELAPSED_MS" >> "$RESULTS/osslclient-sw-$i.log"
  grep -q "Verify return code: 0" "$RESULTS/osslclient-sw-$i.log" && OK=$((OK + 1))
done
wait "$LISTENER_PID" 2>/dev/null
"$BIN" cleanup --label se-spike-exp-latency > /dev/null 2>&1

SERVER_READY=$(grep -c "EVENT type=ready role=server" "$RESULTS/listener-sw-latency.log")
echo "software-key listener: openssl s_client handshakes completed: $OK/20; server-side ready events: $SERVER_READY/20" | tee -a "$RESULTS/summary.txt"
grep "EVENT type=ready role=server" "$RESULTS/listener-sw-latency.log" | sed 's/.*elapsed_ms=/server_elapsed_ms=/' | tee -a "$RESULTS/summary.txt"

echo
echo "raw logs + this summary are under $RESULTS"
echo "workdir kept at $WORK for manual follow-up; delete manually when done"
