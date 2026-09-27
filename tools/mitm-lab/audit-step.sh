#!/usr/bin/env bash
# audit-step.sh (D-39 convention) for tools/mitm-lab — scenario-runner self-test.
# Concrete production scenarios (E15-09/10/11/20) aren't merged yet, so ci and full both run the
# scaffold self-test against openssl stand-ins until then.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/selftest/run.sh"
