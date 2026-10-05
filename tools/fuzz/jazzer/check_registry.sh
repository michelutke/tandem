#!/usr/bin/env bash
# E71-04: fails (exit 1) naming every proto file without a Jazzer registry entry.
#
#   tools/fuzz/jazzer/check_registry.sh [proto-dir] [registry-source]
#
# Defaults to protocol/proto/tandem/v1 and DomainFuzzRegistry.kt. Exit 2: usage or missing input.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
PROTO_DIR="${1:-$REPO_ROOT/protocol/proto/tandem/v1}"
REGISTRY="${2:-$REPO_ROOT/android/core/protocol/src/test/kotlin/dev/tandem/core/protocol/fuzz/DomainFuzzRegistry.kt}"

if [ ! -d "$PROTO_DIR" ] || [ ! -f "$REGISTRY" ]; then
  echo "check_registry.sh: proto dir or registry source not found" >&2
  exit 2
fi

status=0
found=0
for proto in "$PROTO_DIR"/*.proto; do
  [ -e "$proto" ] || continue
  found=1
  name="$(basename "$proto")"
  if ! grep -q "file = \"$name\"" "$REGISTRY"; then
    echo "check_registry.sh: no Jazzer registry entry for $name" >&2
    status=1
  fi
done
if [ "$found" -eq 0 ]; then
  echo "check_registry.sh: no .proto files in $PROTO_DIR" >&2
  exit 2
fi
exit "$status"
