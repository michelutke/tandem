#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ruby "$repo_root/tools/lint/release-log-check.rb" "$@"
