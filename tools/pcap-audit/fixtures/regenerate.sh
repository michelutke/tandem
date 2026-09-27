#!/usr/bin/env bash
# Regenerates the fixture pcaps in this directory deterministically from local loopback TLS
# and TCP traffic (E15-04, E15-06). Requires tshark, openssl, nc and python3 on PATH; captures on
# lo0 (may require BPF device permission — see tools/pcap-audit/README.md).
#
#   tools/pcap-audit/fixtures/regenerate.sh
#
# Fixtures are structural (a real TLS 1.3 handshake, a real TLS 1.2 handshake, a plaintext TCP
# payload, and three plaintext canary-string captures) — the certificate/keys used to generate
# them are throwaway and not committed. The canary fixtures embed a fixed, non-secret
# `TANDEM-CANARY-...` string (not a real pairing/session canary) purely as structural test data.
set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TLS13_PORT=15444
TLS12_PORT=15443
PLAINTEXT_PORT=15445
CANARY_SINGLE_PORT=15446
CANARY_OTHER_PORT=15447
CANARY_SPLIT_PORT=15448

CANARY="TANDEM-CANARY-0123456789abcdef0123456789abcdef"

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

echo "capturing canary-in-single-payload fixture..."
tshark -i lo0 -f "tcp port ${CANARY_SINGLE_PORT}" -w "$FIXTURES_DIR/canary-single-payload.pcapng" \
  -a duration:5 >"tshark-canary-single.log" 2>&1 &
tshark_pid=$!
sleep 1
nc -l "$CANARY_SINGLE_PORT" >/dev/null 2>&1 &
nc_pid=$!
sleep 1
printf 'before %s after\n' "$CANARY" | nc -w1 127.0.0.1 "$CANARY_SINGLE_PORT" || true
sleep 2
kill "$nc_pid" >/dev/null 2>&1 || true
wait "$tshark_pid" 2>/dev/null || true

echo "capturing canary-on-non-tandem-port fixture..."
tshark -i lo0 -f "tcp port ${CANARY_OTHER_PORT}" -w "$FIXTURES_DIR/canary-non-tandem-port.pcapng" \
  -a duration:5 >"tshark-canary-other.log" 2>&1 &
tshark_pid=$!
sleep 1
nc -l "$CANARY_OTHER_PORT" >/dev/null 2>&1 &
nc_pid=$!
sleep 1
printf 'incident on unrelated port: %s\n' "$CANARY" | nc -w1 127.0.0.1 "$CANARY_OTHER_PORT" || true
sleep 2
kill "$nc_pid" >/dev/null 2>&1 || true
wait "$tshark_pid" 2>/dev/null || true

echo "capturing canary-split-across-two-segments fixture..."
tshark -i lo0 -f "tcp port ${CANARY_SPLIT_PORT}" -w "$FIXTURES_DIR/canary-split-segments.pcapng" \
  -a duration:6 >"tshark-canary-split.log" 2>&1 &
tshark_pid=$!
sleep 1
python3 - "$CANARY_SPLIT_PORT" "$CANARY" <<'PYEOF'
import socket
import sys
import threading
import time

port = int(sys.argv[1])
canary = sys.argv[2]
mid = len(canary) // 2


def serve() -> None:
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(1)
    conn, _ = srv.accept()
    conn.settimeout(5)
    try:
        while conn.recv(4096):
            pass
    except socket.timeout:
        pass
    conn.close()
    srv.close()


server_thread = threading.Thread(target=serve)
server_thread.start()
time.sleep(0.3)

s = socket.create_connection(("127.0.0.1", port))
s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
s.sendall(("first-part " + canary[:mid]).encode("ascii"))
time.sleep(0.5)
s.sendall((canary[mid:] + " last-part\n").encode("ascii"))
s.close()
server_thread.join(timeout=5)
PYEOF
sleep 2
kill "$tshark_pid" >/dev/null 2>&1 || true
wait "$tshark_pid" 2>/dev/null || true

echo "done:"
ls -la "$FIXTURES_DIR"/*.pcapng
