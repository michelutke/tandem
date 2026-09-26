#!/usr/bin/env bash
# E15-18: audit step for nmap-phone-check (E15-12).
# Invoked as: audit-step.sh --subset ci|full

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NMAP_SCRIPT="${SCRIPT_DIR}/nmap-phone-check.sh"

SUBSET="${2:-full}"

if [[ "$SUBSET" == "ci" ]]; then
  # In CI, skip the live scan; nmap on a physical phone is a manual gate only.
  echo "MANUAL-GATE: docs/testing/manual-gates.md#e15-12"
  exit 0
fi

if [[ "$SUBSET" == "full" ]]; then
  # Full run would include the actual nmap scan against a live phone,
  # but that requires physical access and is a manual gate.
  echo "MANUAL-GATE: docs/testing/manual-gates.md#e15-12"
  exit 0
fi

echo "ERROR: unknown subset ${SUBSET}" >&2
exit 1
