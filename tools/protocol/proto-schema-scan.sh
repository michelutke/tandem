#!/bin/bash
# Proto schema scanner: fails if any message, enum, or channel name matches debug|echo|loopback|test|canary
# See E01-15 (AC-11: no debug-only protocol path)

set -euo pipefail

readonly ALLOWLIST_FILE="${1:-.}/tools/protocol/proto-schema-scan-allowlist.txt"
readonly PROTO_ROOT="${2:-.}/protocol/proto"

# Read allowlist into memory (one entry per line, empty lines and # comments ignored)
read_allowlist() {
  if [[ ! -f "$ALLOWLIST_FILE" ]]; then
    return
  fi
  grep -v '^\s*#' "$ALLOWLIST_FILE" | grep -v '^\s*$' || true
}

# Extract message, enum type, rpc names, and enum value names from proto files
extract_names() {
  # Extract message, enum type, and rpc names
  find "$PROTO_ROOT" -name "*.proto" -type f \
    | xargs grep -hE '^[[:space:]]*(message|enum|rpc)[[:space:]]+' \
    | sed -E 's/^[[:space:]]*(message|enum|rpc)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/'

  # Extract enum value names (e.g., CHANNEL_DEBUG = 0;)
  find "$PROTO_ROOT" -name "*.proto" -type f \
    | xargs grep -hE '^[[:space:]]+[A-Z_][A-Z0-9_]*[[:space:]]*=' \
    | sed -E 's/^[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]*=.*/\1/' \
    | sort -u
}

# Check if name matches forbidden pattern (case-insensitive)
matches_pattern() {
  local name="$1"
  local lower_name
  lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  if echo "$lower_name" | grep -qiE 'debug|echo|loopback|test|canary'; then
    return 0
  fi
  return 1
}

main() {
  local allowlist
  allowlist=$(read_allowlist)

  local violations=()
  while IFS= read -r name; do
    # Check if name matches the forbidden pattern
    if matches_pattern "$name"; then
      # Check if it's in the allowlist
      if echo "$allowlist" | grep -qx "$name"; then
        continue
      fi
      violations+=("$name")
    fi
  done < <(extract_names)

  if [[ ${#violations[@]} -gt 0 ]]; then
    echo "proto-schema-scan: forbidden debug/test names found:" >&2
    printf '%s\n' "${violations[@]}" >&2
    exit 1
  fi
}

main
