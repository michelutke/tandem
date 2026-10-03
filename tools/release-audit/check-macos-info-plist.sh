#!/bin/bash
# E21-03: Check macOS Info.plist Local Network privacy keys

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Verify TandemApp Info.plist
ruby "$SCRIPT_DIR/check-macos-info-plist.rb" \
  --info-plist "$REPO_ROOT/macos/TandemApp/Info.plist"

# Verify TandemShare Info.plist activation rule (E40-22)
ruby "$SCRIPT_DIR/check-macos-info-plist.rb" --share \
  --info-plist "$REPO_ROOT/macos/TandemShare/Info.plist"

echo "✓ macOS Info.plist Local Network privacy check passed"
