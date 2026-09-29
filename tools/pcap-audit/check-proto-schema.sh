#!/usr/bin/env bash
# tools/pcap-audit/check-proto-schema.sh — E15-07 CI check (tdd:
# protoSchema_debugEchoOrTestMessageName_absent): asserts no `message` declaration under
# protocol/proto/** has a name containing Debug, Echo, or Test (AC-11) — there is no test-only wire
# payload for canary injection or anything else (backlog E15-07 notes, cycle 2 decision); every
# canary/harness step rides a real production message.
#
# Usage: check-proto-schema.sh [proto-dir]  (default: <repo>/protocol/proto)
# Exits 0 if no matches are found, 1 (with the offending lines on stdout) otherwise.
set -euo pipefail

CHECK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROTO_DIR="${1:-$CHECK_ROOT/protocol/proto}"

matches="$(grep -rnE '^[[:space:]]*message[[:space:]]+[A-Za-z0-9_]*(Debug|Echo|Test)[A-Za-z0-9_]*[[:space:]]*\{' "$PROTO_DIR" || true)"

if [[ -n "$matches" ]]; then
  echo "$matches"
  exit 1
fi
exit 0
