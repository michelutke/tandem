#!/usr/bin/env bash
# E71-04 tdd:
#   ci: jazzerTargetRegistry_protoFileWithoutTarget_exitsNonZeroNamingFile
#   ci: jazzerTargetRegistry_everyProtoFileRegistered_exitsZero
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$DIR/check_registry.sh"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "FAIL $1" >&2
  exit 1
}

name=jazzerTargetRegistry_everyProtoFileRegistered_exitsZero
"$CHECK" > /dev/null 2>&1 || fail "$name: exited non-zero"
echo "OK $name"

name=jazzerTargetRegistry_protoFileWithoutTarget_exitsNonZeroNamingFile
mkdir "$work/proto"
cp "$REPO_ROOT"/protocol/proto/tandem/v1/*.proto "$work/proto/"
printf 'syntax = "proto3";\n' > "$work/proto/unregistered_fixture.proto"
output="$("$CHECK" "$work/proto" 2>&1)" && fail "$name: exited 0"
echo "$output" | grep -q 'unregistered_fixture.proto' || fail "$name: output does not name the file"
echo "OK $name"
