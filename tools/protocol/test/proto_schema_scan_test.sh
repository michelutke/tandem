#!/usr/bin/env bash
# E01-15 tdd:
#   ci: protoSchemaScan_debugEchoMessageFixture_exitsNonZero
# Test the proto-schema-scan.sh scanner for forbidden debug/test names.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Test 1: forbidden message name (DebugEcho) should fail
scratch_with_debug() {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/protocol/proto/test/v1"
  mkdir -p "$dir/tools/protocol"
  cp "$REPO_ROOT/tools/protocol/proto-schema-scan-allowlist.txt" "$dir/tools/protocol/"
  cat > "$dir/protocol/proto/test/v1/test.proto" << 'EOF'
syntax = "proto3";
package tandem.v1.test;

message DebugEcho {
  string message = 1;
}
EOF
  echo "$dir"
}

# Test 2: forbidden enum VALUE name (CHANNEL_DEBUG) should fail
scratch_with_debug_value() {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/protocol/proto/test/v1"
  mkdir -p "$dir/tools/protocol"
  cp "$REPO_ROOT/tools/protocol/proto-schema-scan-allowlist.txt" "$dir/tools/protocol/"
  cat > "$dir/protocol/proto/test/v1/test.proto" << 'EOF'
syntax = "proto3";
package tandem.v1.test;

enum TestEnum {
  CHANNEL_DEBUG = 0;
  CHANNEL_NORMAL = 1;
}
EOF
  echo "$dir"
}

# Test 3: clean fixture (no forbidden names)
scratch_clean() {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/protocol/proto/test/v1"
  mkdir -p "$dir/tools/protocol"
  cp "$REPO_ROOT/tools/protocol/proto-schema-scan-allowlist.txt" "$dir/tools/protocol/"
  cat > "$dir/protocol/proto/test/v1/test.proto" << 'EOF'
syntax = "proto3";
package tandem.v1.test;

message Status {
  string code = 1;
}
EOF
  echo "$dir"
}

# Test 4: allowlisted forbidden name should pass
scratch_with_allowlist() {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/protocol/proto/test/v1"
  mkdir -p "$dir/tools/protocol"
  cat > "$dir/tools/protocol/proto-schema-scan-allowlist.txt" << 'EOF'
# Test allowlist
DebugEcho
EOF
  cat > "$dir/protocol/proto/test/v1/test.proto" << 'EOF'
syntax = "proto3";
package tandem.v1.test;

message DebugEcho {
  string message = 1;
}
EOF
  echo "$dir"
}

expect_fail() {
  local name="$1" dir="$2"
  if "$REPO_ROOT/tools/protocol/proto-schema-scan.sh" "$dir" "$dir" >/dev/null 2>&1; then
    echo "FAIL $name: scanner passed" >&2
    exit 1
  fi
  echo "OK $name"
}

expect_pass() {
  local name="$1" dir="$2"
  if ! "$REPO_ROOT/tools/protocol/proto-schema-scan.sh" "$dir" "$dir" >/dev/null 2>&1; then
    echo "FAIL $name: scanner failed" >&2
    exit 1
  fi
  echo "OK $name"
}

# Test 1: forbidden message name
d="$(scratch_with_debug)"
expect_fail protoSchemaScan_debugEchoMessageFixture_exitsNonZero "$d"
rm -rf "$d"

# Test 2: forbidden enum VALUE name
d="$(scratch_with_debug_value)"
expect_fail protoSchemaScan_debugEnumValue_exitsNonZero "$d"
rm -rf "$d"

# Test 3: clean fixture
d="$(scratch_clean)"
expect_pass protoSchemaScan_cleanFixture_exitsZero "$d"
rm -rf "$d"

# Test 4: allowlisted name
d="$(scratch_with_allowlist)"
expect_pass protoSchemaScan_allowlistedName_exitsZero "$d"
rm -rf "$d"
