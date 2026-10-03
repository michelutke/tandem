#!/bin/bash
# E40-22 tdd: ci: shareExtensionBinary_linkedLibraries_excludeNetworkAndTransport

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/../check-share-linked-libraries.sh"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail_count=0

expect() {
  local name="$1" want="$2" binary="$3"
  if "$CHECKER" "$binary" > /dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    echo "✓ $name"
  else
    echo "✗ $name (expected $want)"
    fail_count=$((fail_count + 1))
  fi
}

echo 'import Foundation; print("x")' > "$WORK_DIR/plain.swift"
printf 'import Network\nprint(NWEndpoint.Port(rawValue: 1) as Any)\n' > "$WORK_DIR/network.swift"
printf 'enum TandemTransport { static func f() {} }\nTandemTransport.f()\n' > "$WORK_DIR/transport.swift"
for name in plain network transport; do
  swiftc -Onone "$WORK_DIR/$name.swift" -o "$WORK_DIR/$name" 2> /dev/null
done

expect "plain binary passes" pass "$WORK_DIR/plain"
expect "Network.framework binary fails" fail "$WORK_DIR/network"
expect "TandemTransport binary fails" fail "$WORK_DIR/transport"

[ "$fail_count" -eq 0 ]
