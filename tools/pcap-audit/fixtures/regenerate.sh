#!/usr/bin/env bash
# Regenerates the fixture pcaps in this directory deterministically from local loopback TLS
# traffic (E15-04). Requires tshark, openssl and nc on PATH; captures on lo0 (may require BPF
# device permission — see tools/pcap-audit/README.md).
#
#   tools/pcap-audit/fixtures/regenerate.sh
#
# Fixtures are structural (a real TLS 1.3 handshake, a real TLS 1.2 handshake, a plaintext TCP
# payload) — the certificate/keys used to generate them are throwaway and not committed.
set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TLS13_PORT=15444
TLS12_PORT=15443
PLAINTEXT_PORT=15445

cd "$WORK_DIR"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout key.pem -out cert.pem -days 1 -nodes -subj "/CN=pcap-audit-fixture" >/dev/null 2>&1

capture_tls() {
  local port="$1" version_flag="$2" out="$3"
  tshark -i lo0 -f "tcp port ${port}" -w "$out" -a duration:5 >"tshark-${port}.log" 2>&1 &
  local tshark_pid=$!
  sleep 1
  openssl s_server -accept "$port" -cert cert.pem -key key.pem "$version_flag" -quiet \
    >"s_server-${port}.log" 2>&1 &
  local server_pid=$!
  sleep 1
  printf 'hi\n' | timeout 2 openssl s_client -connect "127.0.0.1:${port}" "$version_flag" -quiet \
    >"s_client-${port}.log" 2>&1 || true
  sleep 2
  kill "$server_pid" >/dev/null 2>&1 || true
  wait "$tshark_pid" 2>/dev/null || true
}

echo "capturing TLS 1.3 handshake fixture..."
capture_tls "$TLS13_PORT" -tls1_3 "$FIXTURES_DIR/tls13-handshake.pcapng"

echo "capturing TLS 1.2 handshake fixture..."
capture_tls "$TLS12_PORT" -tls1_2 "$FIXTURES_DIR/tls12-handshake.pcapng"

echo "capturing plaintext TCP payload fixture..."
tshark -i lo0 -f "tcp port ${PLAINTEXT_PORT}" -w "$FIXTURES_DIR/plaintext-payload.pcapng" \
  -a duration:5 >"tshark-plain.log" 2>&1 &
tshark_pid=$!
sleep 1
nc -l "$PLAINTEXT_PORT" >/dev/null 2>&1 &
nc_pid=$!
sleep 1
printf 'HELLO-PLAINTEXT-PAYLOAD\n' | nc -w1 127.0.0.1 "$PLAINTEXT_PORT" || true
sleep 2
kill "$nc_pid" >/dev/null 2>&1 || true
wait "$tshark_pid" 2>/dev/null || true

echo "done:"
ls -la "$FIXTURES_DIR"/*.pcapng
