#!/usr/bin/env bash
# E00-17 tdd:
#   ci: sensitiveSymbolsList_cycle4Symbols_allPresent
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIST="$ROOT/tools/lint/sensitive-symbols.txt"

CYCLE4_SYMBOLS=(
  pairingSecret qrPayload mediaTicket channelBinding fileName displayName deviceName
  replyText smsBody smsAddress contactName phoneNumber callerNumber inputText inputCoordinates
)

missing=()
for symbol in "${CYCLE4_SYMBOLS[@]}"; do
  grep -qx "$symbol" "$LIST" || missing+=("$symbol")
done

if [ "${#missing[@]}" -ne 0 ]; then
  echo "FAIL sensitiveSymbolsList_cycle4Symbols_allPresent: missing ${missing[*]}" >&2
  exit 1
fi
echo "OK sensitiveSymbolsList_cycle4Symbols_allPresent"
