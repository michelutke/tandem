#!/usr/bin/env bash
set -euo pipefail

# tools/protocol/generate.sh — regenerates protobuf-kotlin-lite (Android) and swift-protobuf
# (macOS) sources from protocol/proto/**/*.proto via protocol/buf.gen.yaml (E00-09). A Gradle or
# Xcode pre-build phase can call this directly. Generated code is committed: never hand-edit it,
# change the .proto and rerun this script instead (checked by tools/protocol/check_generated.rb).
#
#   tools/protocol/generate.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPO_ROOT/protocol"
exec buf generate
