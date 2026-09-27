#!/usr/bin/env bash
# audit-step.sh (D-39 convention) for tools/conformance — protocol/vectors against both codecs.
# Accepts --subset ci|full; conformance is already fast, both subsets run the same full check.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run.sh"
