#!/usr/bin/env bash
# E71-14: macOS egress audit of the Tandem app and share extension during a session. Captures every
# flow of the given pids with `tcpdump -i pktap -Q "pid=<pid>"` (needs root; run by the owner on a
# release build, never in CI) and feeds it to egress-audit.rb.
#
#   sudo tools/release-audit/mac-egress-audit.sh --peer <phone-address> --port <tandem-port> \
#     --out <capture.pcap> --pid <pid> [--pid <pid> ...]      # Ctrl-C ends the capture
#   tools/release-audit/mac-egress-audit.sh --peer <addr> --port <port> --analyze <capture.pcap>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PEER="" PORT="" OUT="" ANALYZE="" PIDS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --peer) PEER="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --pid) PIDS+=("$2"); shift 2 ;;
    --analyze) ANALYZE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$PEER" ] || [ -z "$PORT" ] || { [ -z "$ANALYZE" ] && { [ -z "$OUT" ] || [ ${#PIDS[@]} -eq 0 ]; }; }; then
  sed -n '2,10p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi

if [ -z "$ANALYZE" ]; then
  filter=""
  for pid in "${PIDS[@]}"; do filter="${filter:+$filter or }pid=$pid"; done
  tcpdump -i pktap -Q "$filter" -w "$OUT" || true
  ANALYZE="$OUT"
fi

fields="$(mktemp)"
trap 'rm -f "$fields"' EXIT
tshark -r "$ANALYZE" -T fields -e ip.src -e ip.dst -e ipv6.src -e ipv6.dst \
  -e tcp.srcport -e tcp.dstport -e udp.srcport -e udp.dstport -Y "tcp or udp" >"$fields"
ruby "$ROOT/tools/release-audit/egress-audit.rb" flows --side mac --peer "$PEER" --port "$PORT" "$fields"
