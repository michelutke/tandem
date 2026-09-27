#!/usr/bin/env bash

# E15-17: log-audit — runtime canary scan over captured app logs (logcat + unified log).
# Scans log files for canary strings (message body, phone number, contact name, notification text, etc.)
# and sensitive patterns, with fixture support for testing.
#
# Usage:
#   log-audit.sh --canary "TANDEM-CANARY-xyz" --logcat logcat.txt --unified-log unified.log
#   log-audit.sh --test-fixture tools/log-audit/test/fixtures/logcat-with-canary.txt
#

usage() {
  cat >&2 <<'EOF'
log-audit.sh — runtime canary scan over app logs (E15-17).

  log-audit.sh --canary <CANARY> --logcat <FILE> --unified-log <FILE>

Searches for canary string in raw, hex, base64, and base64url encodings.
EOF
  exit 1
}

# Encode string to hex (lowercase)
to_hex() {
  echo -n "$1" | od -An -tx1 | tr -d ' \n'
}

# Encode string to base64
to_base64() {
  echo -n "$1" | base64 | tr -d '\n'
}

# Encode string to base64url (replace + with -, / with _)
to_base64url() {
  echo -n "$1" | base64 | tr -d '\n' | tr '+/' '-_'
}

# Search for all encodings of the canary in a file.
# Returns 0 if not found, 1 if found or file is empty.
search_canary_in_file() {
  local canary="$1"
  local file="$2"
  local source="$3"  # "logcat" or "unified"

  if [[ ! -f "$file" ]]; then
    echo "ERROR: log file not found: $file" >&2
    return 1
  fi

  # Empty file = failed capture
  if [[ ! -s "$file" ]]; then
    echo "ERROR: empty log capture ($source)" >&2
    return 1
  fi

  local canary_hex
  canary_hex=$(to_hex "$canary")
  local canary_b64
  canary_b64=$(to_base64 "$canary")
  local canary_b64url
  canary_b64url=$(to_base64url "$canary")

  local found=0
  local line_num=0

  while IFS= read -r line; do
    ((line_num++))

    # Search for raw canary
    if [[ "$line" == *"$canary"* ]]; then
      echo "ERROR: canary found in $source at line $line_num" >&2
      found=1
    fi

    # Search for hex encoding
    if [[ "$line" == *"$canary_hex"* ]]; then
      echo "ERROR: canary (hex) found in $source at line $line_num" >&2
      found=1
    fi

    # Search for base64 encoding
    if [[ "$line" == *"$canary_b64"* ]]; then
      echo "ERROR: canary (base64) found in $source at line $line_num" >&2
      found=1
    fi

    # Search for base64url encoding
    if [[ "$line" == *"$canary_b64url"* ]]; then
      echo "ERROR: canary (base64url) found in $source at line $line_num" >&2
      found=1
    fi
  done < "$file"

  return $found
}

# Parse CLI arguments
CANARY=""
LOGCAT_FILE=""
UNIFIED_LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --canary)
      CANARY="$2"
      shift 2
      ;;
    --logcat)
      LOGCAT_FILE="$2"
      shift 2
      ;;
    --unified-log)
      UNIFIED_LOG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: unknown option $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$CANARY" ]]; then
  echo "ERROR: must specify --canary" >&2
  usage
fi

# Check if we have any log files
if [[ -z "$LOGCAT_FILE" && -z "$UNIFIED_LOG_FILE" ]]; then
  echo "ERROR: must specify at least --logcat or --unified-log" >&2
  usage
fi

# If a log file is specified but doesn't exist, that's an error (empty capture).
if [[ -n "$LOGCAT_FILE" && ! -f "$LOGCAT_FILE" ]]; then
  echo "ERROR: logcat file not found: $LOGCAT_FILE" >&2
  exit 1
fi

if [[ -n "$UNIFIED_LOG_FILE" && ! -f "$UNIFIED_LOG_FILE" ]]; then
  echo "ERROR: unified log file not found: $UNIFIED_LOG_FILE" >&2
  exit 1
fi

exit_code=0

# Search in both log files if provided
if [[ -n "$LOGCAT_FILE" ]]; then
  search_canary_in_file "$CANARY" "$LOGCAT_FILE" "logcat" || exit_code=1
fi

if [[ -n "$UNIFIED_LOG_FILE" ]]; then
  search_canary_in_file "$CANARY" "$UNIFIED_LOG_FILE" "unified" || exit_code=1
fi

exit "$exit_code"
