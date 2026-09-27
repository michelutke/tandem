#!/bin/bash
# E22-04: Check macOS entitlements for Release build

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Verify TandemApp entitlements
ruby "$SCRIPT_DIR/check-macos-entitlements.rb" \
  --entitlements "$REPO_ROOT/macos/TandemApp/TandemApp.entitlements"

echo "✓ macOS entitlements check passed"
