#!/usr/bin/env bash
# E01-15 tdd:
#   ci: bufBreaking_fieldRenumbered_exitsNonZero
#   ci: bufBreaking_fieldDeletedWithoutReserved_exitsNonZero
# Test buf breaking detection of incompatible proto changes.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

scratch_with_baseline() {
  local dir; dir="$(mktemp -d)"
  # Copy protocol sources
  cp -r "$REPO_ROOT/protocol" "$dir/protocol"
  # Initialize git repo with baseline commit
  (cd "$dir" && git init -q && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm baseline)
  echo "$dir"
}

expect_breaking() {
  local name="$1" dir="$2"
  if (cd "$dir/protocol" && buf breaking --against '../.git#branch=HEAD^,subdir=protocol' >/dev/null 2>&1); then
    echo "FAIL $name: breaking check passed" >&2
    exit 1
  fi
  echo "OK $name"
}

# Test 1: renumber a field (breaking change)
d="$(scratch_with_baseline)"
# Renumber battery_level from 1 to 5 in status.proto
sed -i '' 's/int32 battery_level = 1;/int32 battery_level = 5;/' "$d/protocol/proto/tandem/v1/status.proto"
(cd "$d" && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm "renumber field")
expect_breaking bufBreaking_fieldRenumbered_exitsNonZero "$d"
rm -rf "$d"

# Test 2: delete a field without reserved (breaking change)
d="$(scratch_with_baseline)"
# Delete battery_level without adding it to reserved
sed -i '' '/int32 battery_level = 1;/d' "$d/protocol/proto/tandem/v1/status.proto"
(cd "$d" && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm "delete field")
expect_breaking bufBreaking_fieldDeletedWithoutReserved_exitsNonZero "$d"
rm -rf "$d"
