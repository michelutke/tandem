#!/usr/bin/env bash
# E14-23 spike: generates tandem://pair QR fixture PNGs (PRD F-2.1 payload shape) with qrencode,
# and copies them into every module's androidTest assets so both decoders decode byte-identical
# fixtures. Run once before scripts/run-spike.sh.
#
# Usage: scripts/generate-fixtures.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_DIR="$PROJECT_DIR/fixtures"

command -v qrencode >/dev/null || { echo "qrencode not found (brew install qrencode)"; exit 1; }

mkdir -p "$FIXTURES_DIR"

b64url() {
    openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# Fixture 1: "typical" pairing payload (2 addresses, short Mac name) — this is the one timed
# 20x per decoder for the median/p95 acceptance criterion.
FP1=$(openssl rand 32 | b64url)
S1=$(openssl rand 16 | b64url)
PAYLOAD_TYPICAL="tandem://pair?v=1&fp=${FP1}&s=${S1}&a=192.168.1.23,10.0.0.5&p=7443&n=Michels-MacBook-Pro"
echo -n "$PAYLOAD_TYPICAL" > "$FIXTURES_DIR/typical.txt"
qrencode -o "$FIXTURES_DIR/typical.png" -s 10 -m 2 -l M "$PAYLOAD_TYPICAL"

# Fixture 2: "max" pairing payload — 8 literal IPs (D-18 cap) and a 64-byte name, to check the
# decoder still reads the densest QR the pairing window can produce (correctness only, not timed).
FP2=$(openssl rand 32 | b64url)
S2=$(openssl rand 16 | b64url)
MAXNAME=$(printf 'M%.0s' $(seq 1 64))
ADDRS="10.0.0.1,10.0.0.2,10.0.0.3,10.0.0.4,10.0.0.5,10.0.0.6,10.0.0.7,10.0.0.8"
PAYLOAD_MAX="tandem://pair?v=1&fp=${FP2}&s=${S2}&a=${ADDRS}&p=65535&n=${MAXNAME}"
echo -n "$PAYLOAD_MAX" > "$FIXTURES_DIR/max.txt"
qrencode -o "$FIXTURES_DIR/max.png" -s 10 -m 2 -l M "$PAYLOAD_MAX"

echo "--- fixtures ---"
for f in typical max; do
    echo "$f: $(wc -c < "$FIXTURES_DIR/$f.txt") bytes payload -> $FIXTURES_DIR/$f.png"
done

for module in app-mlkit app-zxing; do
    ASSETS_DIR="$PROJECT_DIR/$module/src/androidTest/assets"
    mkdir -p "$ASSETS_DIR"
    cp "$FIXTURES_DIR/typical.png" "$FIXTURES_DIR/typical.txt" "$FIXTURES_DIR/max.png" "$FIXTURES_DIR/max.txt" "$ASSETS_DIR/"
    echo "copied fixtures into $ASSETS_DIR"
done
