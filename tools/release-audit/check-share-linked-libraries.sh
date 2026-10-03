#!/bin/bash
# E40-22: the Share extension binary must link neither Network.framework nor the transport package.
# Usage: check-share-linked-libraries.sh PATH_TO_EXTENSION_BINARY

set -e

BINARY="${1:?usage: check-share-linked-libraries.sh PATH_TO_EXTENSION_BINARY}"

if otool -L "$BINARY" | grep -q "Network.framework"; then
  echo "Error: $BINARY links Network.framework" >&2
  exit 1
fi

if nm -a "$BINARY" 2>/dev/null | grep -q "TandemTransport"; then
  echo "Error: $BINARY contains TandemTransport symbols" >&2
  exit 1
fi

echo "✓ Share extension links neither Network.framework nor TandemTransport"
