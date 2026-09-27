#!/usr/bin/env bash
# E15-18: audit step for log-audit (E15-17).
# Invoked as: audit-step.sh --subset ci|full

set -e

SUBSET="${2:-full}"

if [[ "$SUBSET" == "ci" ]]; then
  # In CI, log audit is part of the integration test capturing during harness runs.
  # For phase 1, this is a manual gate (real device logs cannot be captured in CI).
  echo "MANUAL-GATE: docs/testing/manual-gates.md#e15-17"
  exit 0
fi

if [[ "$SUBSET" == "full" ]]; then
  # Full run includes live device log capture and scan.
  # This is a manual gate requiring physical devices.
  echo "MANUAL-GATE: docs/testing/manual-gates.md#e15-17"
  exit 0
fi

echo "ERROR: unknown subset ${SUBSET}" >&2
exit 1
