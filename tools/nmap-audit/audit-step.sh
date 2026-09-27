#!/usr/bin/env bash
# E15-18: audit step for nmap-phone-check (E15-12). A separate top-level directory (D-39: one
# audit-step.sh per discovered tool) from tools/mitm-lab, where nmap-phone-check.sh's source
# actually lives, since tools/mitm-lab's own audit-step.sh is already the mitm scenario runner.
# Invoked as: audit-step.sh --subset ci|full
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NMAP_SCRIPT="${SCRIPT_DIR}/../mitm-lab/nmap-phone-check.sh"

SUBSET="${2:-full}"

if [[ "$SUBSET" == "ci" || "$SUBSET" == "full" ]]; then
  # nmap on a physical phone is a manual gate only, in both subsets.
  echo "MANUAL-GATE: docs/testing/manual-gates.md#e15-12"
  exit 0
fi

echo "ERROR: unknown subset ${SUBSET}" >&2
exit 1
