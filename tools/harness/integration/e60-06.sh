#!/usr/bin/env bash
# E60-06: pcap-audit over an active control + media connection pair against the real Mac server.
# The JVM harness client opens a control session, obtains a real `MediaTicketGrant` and holds a
# second, ticket-bound media connection (E60-05's `RAWOPEN`/`RAWTICKET`/`MEDIAOPEN ... HOLD`) while
# a capture filtered to the Tandem port runs. Passes only if:
#   pcapAudit_activeMirrorSession_onlyTls13RecordsOnBothConnections   -- tls13_assertion.py passes and
#     flows.py reports two distinct TLS 1.3 flows on the Tandem port (not vacuous);
#   pcapAudit_activeMirrorSession_allTandemFlowsOnSinglePort          -- the Mac process listens on
#     exactly the Tandem port (no second listener) and flows.py found no flow to another port.
# Usage: e60-06.sh [out.pcapng]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../mitm-lab/e60-05-media-ticket/lib/e60-05-common.sh
source "$SCRIPT_DIR/../../mitm-lab/e60-05-media-ticket/lib/e60-05-common.sh"
trap 'e60_05_teardown; [ -n "${TSHARK_PID:-}" ] && kill -INT "$TSHARK_PID" 2>/dev/null; [ -n "${TSHARK_LOG:-}" ] && rm -f "$TSHARK_LOG"' EXIT

PCAP_AUDIT_DIR="$E60_05_ROOT/tools/pcap-audit"
TSHARK="${TSHARK_BIN:-tshark}"
TSHARK_PID=""
TSHARK_LOG=""
FAILED=0

e60_05_setup
OUT_PCAP="${1:-$E15_10_TMP_DIR/e60-06.pcapng}"

TSHARK_LOG="$(mktemp)"
"$TSHARK" -i lo0 -f "tcp port $PORT" -w "$OUT_PCAP" 2>"$TSHARK_LOG" &
TSHARK_PID=$!
for _ in $(seq 1 150); do
  grep -q "Capturing on" "$TSHARK_LOG" 2>/dev/null && break
  kill -0 "$TSHARK_PID" 2>/dev/null || break
  sleep 0.1
done
sleep 0.5

e60_05_open_control || FAILED=1
if [ "$FAILED" -eq 0 ]; then
  e60_05_request_ticket || FAILED=1
fi
if [ "$FAILED" -eq 0 ]; then
  e60_05_media_open A "$E60_05_TICKET" HOLD || FAILED=1
  e15_10_wait_for_log_line 'harness-media-event: bound' 10 >/dev/null || { e60_05_log "FAIL: media connection was not bound"; FAILED=1; }
fi

if [ "$FAILED" -eq 0 ]; then
  listeners="$(lsof -nP -a -p "$HARNESS_PID" -iTCP -sTCP:LISTEN -Fn 2>/dev/null | sed -n 's/^n.*:\([0-9][0-9]*\)$/\1/p' | sort -u)"
  if [ "$listeners" != "$PORT" ]; then
    e60_05_log "FAIL: Mac listens on [$listeners], expected only $PORT"
    FAILED=1
  fi
fi

sleep 1
kill -INT "$TSHARK_PID" 2>/dev/null || true
wait "$TSHARK_PID" 2>/dev/null || true
TSHARK_PID=""

if [ "$FAILED" -eq 0 ]; then
  python3 "$PCAP_AUDIT_DIR/tls13_assertion.py" "$OUT_PCAP" --port "$PORT" || FAILED=1
  python3 "$PCAP_AUDIT_DIR/flows.py" "$OUT_PCAP" --port "$PORT" --min-flows 2 || FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  e60_05_log "OK: control + media flows are TLS 1.3 only, on the single Tandem port"
  exit 0
fi
e60_05_log "FAILED"
exit 1
