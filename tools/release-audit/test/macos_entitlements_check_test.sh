#!/bin/bash
# E22-04: macOS entitlements check test suite

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHECKER="$REPO_ROOT/tools/release-audit/check-macos-entitlements.rb"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

test_count=0
pass_count=0
fail_count=0

run_test() {
  local test_name="$1"
  local fixture="$2"
  local should_pass="$3"

  test_count=$((test_count + 1))

  if [ "$should_pass" = "pass" ]; then
    if ruby "$CHECKER" --entitlements "$fixture" > /dev/null 2>&1; then
      echo "✓ $test_name"
      pass_count=$((pass_count + 1))
    else
      echo "✗ $test_name (expected to pass but failed)"
      fail_count=$((fail_count + 1))
    fi
  else
    if ! ruby "$CHECKER" --entitlements "$fixture" > /dev/null 2>&1; then
      echo "✓ $test_name"
      pass_count=$((pass_count + 1))
    else
      echo "✗ $test_name (expected to fail but passed)"
      fail_count=$((fail_count + 1))
    fi
  fi
}

echo "Running macOS entitlements check tests..."
echo

run_test "exact 3 entitlements" "$FIXTURES_DIR/exact-3-entitlements.plist" "pass"
run_test "extra entitlement fails" "$FIXTURES_DIR/extra-entitlement.plist" "fail"
run_test "missing network.server fails" "$FIXTURES_DIR/missing-network-server.plist" "fail"
run_test "get-task-allow forbidden" "$FIXTURES_DIR/get-task-allow.plist" "fail"

echo
echo "Results: $pass_count passed, $fail_count failed out of $test_count tests"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

exit 0
