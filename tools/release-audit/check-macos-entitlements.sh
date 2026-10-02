#!/bin/bash
# E22-04 / E71-09: Check macOS entitlements for the Release app and the share extension

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ruby "$SCRIPT_DIR/check-macos-entitlements.rb" \
  --entitlements "$REPO_ROOT/macos/TandemApp/TandemApp.entitlements" --target app
ruby "$SCRIPT_DIR/check-macos-entitlements.rb" \
  --entitlements "$REPO_ROOT/macos/TandemShare/TandemShare.entitlements" --target share

echo "✓ macOS entitlements check passed"
