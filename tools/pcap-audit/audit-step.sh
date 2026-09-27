#!/usr/bin/env bash
# audit-step.sh (D-39 convention) for tools/pcap-audit — capture/parse primitive tests.
# The TLS-1.3-only assertion (E15-05) and canary scan (E15-06) build on analyze.py and are not
# merged yet, so ci and full both run this package's own pytest suite until then.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv=/tmp/audit-step-pcap-venv
[ -d "$venv" ] || python3 -m venv "$venv" >/dev/null
"$venv/bin/pip" -q install -r "$here/requirements.txt" pytest
"$venv/bin/python" -m pytest -q "$here/tests"
