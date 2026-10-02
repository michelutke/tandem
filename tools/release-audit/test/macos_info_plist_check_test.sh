#!/bin/bash
# E21-03 tdd: ci: infoPlist_localNetworkKeys_containUsageDescriptionAndTandemService

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHECKER="$REPO_ROOT/tools/release-audit/check-macos-info-plist.rb"
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
    if ruby "$CHECKER" --info-plist "$fixture" > /dev/null 2>&1; then
      echo "✓ $test_name"
      pass_count=$((pass_count + 1))
    else
      echo "✗ $test_name (expected to pass but failed)"
      fail_count=$((fail_count + 1))
    fi
  else
    if ! ruby "$CHECKER" --info-plist "$fixture" > /dev/null 2>&1; then
      echo "✓ $test_name"
      pass_count=$((pass_count + 1))
    else
      echo "✗ $test_name (expected to fail but passed)"
      fail_count=$((fail_count + 1))
    fi
  fi
}

echo "Running macOS Info.plist Local Network privacy check tests..."
echo

run_test "usage description and tandem service present" "$FIXTURES_DIR/info-plist-with-local-network-keys.plist" "pass"
run_test "missing usage description fails" "$FIXTURES_DIR/info-plist-missing-usage-description.plist" "fail"
run_test "missing NSBonjourServices fails" "$FIXTURES_DIR/info-plist-missing-bonjour-services.plist" "fail"
run_test "wrong bonjour service fails" "$FIXTURES_DIR/info-plist-wrong-bonjour-service.plist" "fail"
run_test "NSAllowsLocalNetworking fails" "$FIXTURES_DIR/info-plist-allows-local-networking.plist" "fail"
run_test "NSAllowsArbitraryLoads fails" "$FIXTURES_DIR/info-plist-allows-arbitrary-loads.plist" "fail"
run_test "checked-in TandemApp Info.plist passes" "$REPO_ROOT/macos/TandemApp/Info.plist" "pass"

echo
echo "Results: $pass_count passed, $fail_count failed out of $test_count tests"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

exit 0
