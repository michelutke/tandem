#!/usr/bin/env bash
# tools/pcap-audit/mirror-canary-audit.sh — E61-09: audits a capture taken while TANDEM-CANARY-<random>
# was displayed on the mirrored phone screen (canary.sh mirror step). Passes only if
# canary_scan.py finds zero occurrences anywhere in the capture AND media_volume.py finds at least
# --min-bytes (default 1 MB) of traffic on the Tandem port, so the pass is not vacuous.
# Usage: mirror-canary-audit.sh <pcap> --canary <string> --port <port> [--min-bytes <n>]
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pcap="${1:?usage: mirror-canary-audit.sh <pcap> --canary <string> --port <port> [--min-bytes <n>]}"
shift
canary=""
port=""
min_bytes=1000000
while [[ $# -gt 0 ]]; do
  case "$1" in
    --canary) canary="$2"; shift 2 ;;
    --port) port="$2"; shift 2 ;;
    --min-bytes) min_bytes="$2"; shift 2 ;;
    *) echo "mirror-canary-audit.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$canary" && -n "$port" ]] || { echo "mirror-canary-audit.sh: --canary and --port are required" >&2; exit 2; }

failed=0
python3 "$here/canary_scan.py" "$pcap" --canary "$canary" || failed=1
python3 "$here/media_volume.py" "$pcap" --port "$port" --min-bytes "$min_bytes" || failed=1
exit "$failed"
