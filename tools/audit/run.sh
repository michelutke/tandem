#!/usr/bin/env bash
exec ruby "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run.rb" "$@"
