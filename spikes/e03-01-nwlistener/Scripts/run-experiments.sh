#!/usr/bin/env bash
# Drives the E03-01 acceptance-criteria experiments against a real NWListener process.
# Every criterion is exercised for real (swift run / openssl s_client), 10 times each per the
# backlog's "over 10 runs" go criteria. Results land in Scripts/../results/ next to a
# machine-readable summary.txt that docs/spikes/nwlistener-mtls.md quotes from.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN=.build/debug/nwlistener-spike
OPENSSL=$(command -v /opt/homebrew/bin/openssl 2>/dev/null || command -v openssl)
WORK=$(mktemp -d /tmp/nwl-experiment.XXXXXX)
RESULTS="$(pwd)/results"
rm -rf "$RESULTS"
mkdir -p "$RESULTS"

echo "openssl: $OPENSSL ($($OPENSSL version))" | tee "$RESULTS/summary.txt"
swift build -c debug 2>&1 | tail -5

"$BIN" setup --workdir "$WORK" | tee "$RESULTS/setup.log"

PEM="$WORK/pem"
mkdir -p "$PEM"
for name in server good-client attacker-client; do
  pass=$(cat "$WORK/$name.pass")
  "$OPENSSL" pkcs12 -legacy -in "$WORK/$name.p12" -passin "pass:$pass" -out "$PEM/$name.pem" -nodes 2>/dev/null
  "$OPENSSL" x509 -in "$PEM/$name.pem" -out "$PEM/$name-cert.pem"
  sed -n '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/p' "$PEM/$name.pem" > "$PEM/$name-key.pem"
done

start_listener() {
  local logfile=$1; shift
  "$BIN" listen --workdir "$WORK" "$@" > "$RESULTS/$logfile" 2>&1 &
  echo $!
}

wait_ready() {
  local logfile=$1
  for _ in $(seq 1 50); do
    grep -q "listener-state state=ready" "$RESULTS/$logfile" 2>/dev/null && return 0
    sleep 0.1
  done
  echo "listener never reached ready: $logfile" >&2
  return 1
}

stop_listener() {
  local pid=$1
  wait "$pid" 2>/dev/null
}

# Some sections make fewer connection attempts than a listener's --exit-after count, so the
# listener would otherwise sit waiting for more; use this instead of stop_listener when the
# exact attempt count isn't guaranteed to reach --exit-after.
kill_listener() {
  local pid=$1
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

section() { echo; echo "=== $1 ===" | tee -a "$RESULTS/summary.txt"; }

########################################################################
section "1. good client, correct pin (sanity + exporter baseline), 10 runs"
PID=$(start_listener listener-good.log --port 4501 --exit-after 10 --handshake-deadline 5)
wait_ready listener-good.log
PASS=0
for i in $(seq 1 10); do
  "$BIN" client --workdir "$WORK" --port 4501 --identity good-client --timeout 5 > "$RESULTS/client-good-$i.log" 2>&1
  grep -q "EVENT type=ready role=client" "$RESULTS/client-good-$i.log" && PASS=$((PASS + 1))
done
stop_listener "$PID"
echo "good-client reached ready: $PASS/10" | tee -a "$RESULTS/summary.txt"

EXPORTER_MATCHES=0
for i in $(seq 1 10); do
  c=$(grep -o 'exporter_sha256=[0-9a-f]*' "$RESULTS/client-good-$i.log" | head -1 | cut -d= -f2)
  port=$(grep -o 'role=client tls_version.*' "$RESULTS/client-good-$i.log" >/dev/null; true)
  s=$(grep "exporter_sha256=" "$RESULTS/listener-good.log" | sed -n "${i}p" | grep -o 'exporter_sha256=[0-9a-f]*' | cut -d= -f2)
  if [ -n "$c" ] && [ "$c" = "$s" ]; then EXPORTER_MATCHES=$((EXPORTER_MATCHES + 1)); fi
done
echo "exporter sha256 matches client<->server (positional pairing): $EXPORTER_MATCHES/10" | tee -a "$RESULTS/summary.txt"

########################################################################
section "2. unpinned client cert (attacker), 10 runs -- expect verify_block reject, 0 app bytes"
PID=$(start_listener listener-attacker.log --port 4502 --exit-after 10 --handshake-deadline 5)
wait_ready listener-attacker.log
REJECT=0
for i in $(seq 1 10); do
  "$BIN" client --workdir "$WORK" --port 4502 --identity attacker-client --timeout 5 > "$RESULTS/client-attacker-$i.log" 2>&1
  grep -q "EVENT type=failed role=client" "$RESULTS/client-attacker-$i.log" && REJECT=$((REJECT + 1))
done
stop_listener "$PID"
APPDATA=$(grep -c "EVENT type=app-data role=server" "$RESULTS/listener-attacker.log")
VERIFYFALSE=$(grep -c "verify_block:.*match=false" "$RESULTS/listener-attacker.log")
echo "attacker (unpinned) client rejected: $REJECT/10; verify_block match=false count=$VERIFYFALSE/10; server-side app-data events (want 0)=$APPDATA" | tee -a "$RESULTS/summary.txt"

########################################################################
section "3. no client certificate at all, 10 runs -- expect rejection"
PID=$(start_listener listener-nocert.log --port 4503 --exit-after 10 --handshake-deadline 5)
wait_ready listener-nocert.log
CLIENT_TERMINAL=0
for i in $(seq 1 10); do
  "$BIN" client --workdir "$WORK" --port 4503 --identity none --timeout 5 --no-server-pin > "$RESULTS/client-nocert-$i.log" 2>&1
  grep -qE "EVENT type=(failed|waiting) role=client" "$RESULTS/client-nocert-$i.log" && CLIENT_TERMINAL=$((CLIENT_TERMINAL + 1))
done
stop_listener "$PID"
SERVER_REJECT=$(grep -c "EVENT type=failed role=server" "$RESULTS/listener-nocert.log")
SERVER_APPDATA=$(grep -c "EVENT type=app-data role=server" "$RESULTS/listener-nocert.log")
echo "no-client-certificate: server rejected $SERVER_REJECT/10 (app-data delivered=$SERVER_APPDATA, want 0); client observed failed/waiting $CLIENT_TERMINAL/10 (Network.framework reports this as .waiting not .failed on the client -- see findings doc)" | tee -a "$RESULTS/summary.txt"

########################################################################
section "4. openssl s_client -tls1_2 against TLS-1.3-only listener, 10 runs -- expect rejection"
PID=$(start_listener listener-tls12.log --port 4504 --exit-after 10 --handshake-deadline 5)
wait_ready listener-tls12.log
FAIL=0
for i in $(seq 1 10); do
  out=$("$OPENSSL" s_client -connect 127.0.0.1:4504 -tls1_2 -cert "$PEM/good-client-cert.pem" -key "$PEM/good-client-key.pem" -alpn tandem/1 </dev/null 2>&1)
  echo "$out" > "$RESULTS/osslient-tls12-$i.log"
  if ! echo "$out" | grep -q "^ *Protocol *: *TLSv1\.2$"; then
    FAIL=$((FAIL + 1))
  fi
done
stop_listener "$PID"
SERVER_REJECT=$(grep -c "EVENT type=failed role=server" "$RESULTS/listener-tls12.log")
echo "openssl -tls1_2 handshake rejected (no TLSv1.2 session established): $FAIL/10; server-side failed events: $SERVER_REJECT/10" | tee -a "$RESULTS/summary.txt"

########################################################################
section "5. ALPN enforcement, 10 runs each"
PID=$(start_listener listener-alpn.log --port 4505 --exit-after 20 --handshake-deadline 5)
wait_ready listener-alpn.log
NOALPN_REJECT=0
WRONGALPN_REJECT=0
for i in $(seq 1 10); do
  "$BIN" client --workdir "$WORK" --port 4505 --identity good-client --alpn none --timeout 5 > "$RESULTS/client-noalpn-$i.log" 2>&1
  grep -qE "EVENT type=(failed|waiting) role=client" "$RESULTS/client-noalpn-$i.log" && NOALPN_REJECT=$((NOALPN_REJECT + 1))
  "$BIN" client --workdir "$WORK" --port 4505 --identity good-client --alpn other/1 --timeout 5 > "$RESULTS/client-wrongalpn-$i.log" 2>&1
  grep -qE "EVENT type=(failed|waiting) role=client" "$RESULTS/client-wrongalpn-$i.log" && WRONGALPN_REJECT=$((WRONGALPN_REJECT + 1))
done
stop_listener "$PID"
NOALPN_SERVER_READY=$(grep -c "EVENT type=ready role=server" "$RESULTS/listener-alpn.log")
echo "client offering no ALPN: client-side failed/waiting=$NOALPN_REJECT/10; wrong-ALPN client-side failed/waiting=$WRONGALPN_REJECT/10; total server-side READY across both loops (want low; see findings for no-ALPN-accepted gotcha)=$NOALPN_SERVER_READY/20" | tee -a "$RESULTS/summary.txt"

PID=$(start_listener listener-alpn-ok.log --port 4506 --exit-after 10 --handshake-deadline 5)
wait_ready listener-alpn-ok.log
ALPN_OK=0
for i in $(seq 1 10); do
  "$BIN" client --workdir "$WORK" --port 4506 --identity good-client --alpn tandem/1 --timeout 5 > "$RESULTS/client-alpnok-$i.log" 2>&1
  grep -q "alpn=tandem/1" "$RESULTS/client-alpnok-$i.log" && ALPN_OK=$((ALPN_OK + 1))
done
stop_listener "$PID"
echo "client offering tandem/1 negotiates tandem/1: $ALPN_OK/10" | tee -a "$RESULTS/summary.txt"

########################################################################
section "6. session resumption / tickets, 10 connection attempts per listener config"
# tickets=disabled is the production-intended default (see makeTLSOptions). -sess_out only
# ever writes a file if the server actually issued a NewSessionTicket; absence of the file is
# itself direct evidence no ticket was issued (distinct from, and stronger than, grepping for
# "Reused" on a follow-up connect).
PID=$(start_listener listener-resume-disabled.log --port 4507 --exit-after 10 --handshake-deadline 5)
wait_ready listener-resume-disabled.log
NO_TICKET=0
for i in $(seq 1 10); do
  SESSFILE="$WORK/session-disabled-$i.pem"
  rm -f "$SESSFILE"
  "$OPENSSL" s_client -connect 127.0.0.1:4507 -tls1_3 -cert "$PEM/good-client-cert.pem" -key "$PEM/good-client-key.pem" -alpn tandem/1 -sess_out "$SESSFILE" </dev/null > "$RESULTS/osslient-resume-disabled-$i.log" 2>&1
  [ -f "$SESSFILE" ] || NO_TICKET=$((NO_TICKET + 1))
done
stop_listener "$PID"
echo "tickets=disabled: no session-ticket file ever written: $NO_TICKET/10 (want 10/10)" | tee -a "$RESULTS/summary.txt"

# Contrast case: explicitly flip tickets on and see whether Apple's stack issues one anyway
# once client-certificate authentication is in play.
PID=$(start_listener listener-resume-enabled.log --port 4517 --exit-after 10 --handshake-deadline 5 --tickets enabled)
wait_ready listener-resume-enabled.log
NO_TICKET_ENABLED=0
REUSED=0
SESSFILE="$WORK/session-enabled.pem"
rm -f "$SESSFILE"
for i in $(seq 1 10); do
  if [ -f "$SESSFILE" ]; then
    "$OPENSSL" s_client -connect 127.0.0.1:4517 -tls1_3 -cert "$PEM/good-client-cert.pem" -key "$PEM/good-client-key.pem" -alpn tandem/1 -sess_in "$SESSFILE" -sess_out "$SESSFILE" </dev/null > "$RESULTS/osslient-resume-enabled-$i.log" 2>&1
    grep -q "^Reused" "$RESULTS/osslient-resume-enabled-$i.log" && REUSED=$((REUSED + 1))
  else
    "$OPENSSL" s_client -connect 127.0.0.1:4517 -tls1_3 -cert "$PEM/good-client-cert.pem" -key "$PEM/good-client-key.pem" -alpn tandem/1 -sess_out "$SESSFILE" </dev/null > "$RESULTS/osslient-resume-enabled-$i.log" 2>&1
  fi
  [ -f "$SESSFILE" ] || NO_TICKET_ENABLED=$((NO_TICKET_ENABLED + 1))
done
kill_listener "$PID"
echo "tickets=enabled (contrast case): no session-ticket file ever written: $NO_TICKET_ENABLED/10; reused-session handshakes: $REUSED/10 (both want 0 tickets issued even with tickets enabled, per client-cert-required TLS 1.3 sessions)" | tee -a "$RESULTS/summary.txt"

########################################################################
section "7. handshake deadline: TCP connects, no TLS bytes ever sent"
PID=$(start_listener listener-deadline.log --port 4508 --exit-after 1 --handshake-deadline 3)
wait_ready listener-deadline.log
( ( sleep 6; echo done ) | nc 127.0.0.1 4508 >/dev/null 2>&1 ) &
NCPID=$!
sleep 5
if grep -q "handshake-deadline-cancel" "$RESULTS/listener-deadline.log"; then
  echo "handshake deadline cancelled a stalled pre-TLS connection: PASS" | tee -a "$RESULTS/summary.txt"
else
  echo "handshake deadline cancelled a stalled pre-TLS connection: FAIL (no cancel event seen)" | tee -a "$RESULTS/summary.txt"
fi
wait $NCPID 2>/dev/null
stop_listener "$PID"

echo
echo "raw logs + this summary are under $RESULTS"
echo "workdir (identities) kept at $WORK for manual follow-up; delete manually when done"
