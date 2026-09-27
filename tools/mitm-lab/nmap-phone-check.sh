#!/usr/bin/env bash

# E15-12: nmap phone-listener check script. Parses nmap XML and fails if any TCP/UDP port
# outside a documented allowlist is open, enforcing invariant 4.
#
# Usage:
#   nmap-phone-check.sh --ip 192.168.1.100
#   nmap-phone-check.sh --test-fixture tools/mitm-lab/test/fixtures/nmap/open-port.xml
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST_FILE="${SCRIPT_DIR}/nmap-allowlist.txt"
PARSER_PY="${SCRIPT_DIR}/nmap-parser.py"

TEMP_NMAP_OUTPUT=""
cleanup() {
  [[ -n "$TEMP_NMAP_OUTPUT" && -f "$TEMP_NMAP_OUTPUT" ]] && rm -f "$TEMP_NMAP_OUTPUT"
}
trap cleanup EXIT

usage() {
  cat >&2 <<'EOF'
nmap-phone-check.sh — verify phone opens no listening sockets (E15-12).

  nmap-phone-check.sh --ip <IP>
  nmap-phone-check.sh --test-fixture <path>

Options:
  --ip <IP>              Scan a phone on the network via nmap -p- -oX.
  --test-fixture <path>  Parse a pre-existing nmap XML file (for unit tests).
EOF
  exit 1
}

load_allowlist() {
  if [[ ! -f "$ALLOWLIST_FILE" ]]; then
    echo "ERROR: allowlist file not found at ${ALLOWLIST_FILE}" >&2
    return 1
  fi
  grep -v '^\s*#' "$ALLOWLIST_FILE" | grep -v '^\s*$'
}

# Parses nmap XML: returns port/proto pairs for open ports.
# Fails if host is reported down.
parse_nmap_xml() {
  local xml_file="$1"

  # Check if host is down (status="down")
  if grep -q 'status state="down"' "$xml_file"; then
    echo "ERROR: host is down/unreachable" >&2
    return 1
  fi

  # Use Python helper to parse XML
  python3 "$PARSER_PY" "$xml_file" || return 1
}

check_ports() {
  local xml_file="$1"
  local allowlist_ports
  allowlist_ports=$(load_allowlist) || return 1

  local open_ports
  open_ports=$(parse_nmap_xml "$xml_file") || return 1

  if [[ -z "$open_ports" ]]; then
    return 0
  fi

  local violations=""
  while IFS= read -r port_proto; do
    [[ -z "$port_proto" ]] && continue

    port="${port_proto%/*}"
    proto="${port_proto#*/}"

    # Check if this port+proto is in the allowlist
    if ! echo "$allowlist_ports" | grep -qx "${port}/${proto}"; then
      violations="${violations}${port}/${proto} "
    fi
  done <<< "$open_ports"

  if [[ -n "$violations" ]]; then
    echo "ERROR: open non-allowlisted ports: ${violations}" >&2
    return 1
  fi

  return 0
}

# Parse CLI arguments
IP=""
TEST_FIXTURE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)
      IP="$2"
      shift 2
      ;;
    --test-fixture)
      TEST_FIXTURE="$2"
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

if [[ -n "$TEST_FIXTURE" ]]; then
  check_ports "$TEST_FIXTURE"
  exit $?
elif [[ -n "$IP" ]]; then
  TEMP_NMAP_OUTPUT=$(mktemp)
  nmap -p- -oX "$TEMP_NMAP_OUTPUT" "$IP" > /dev/null
  check_ports "$TEMP_NMAP_OUTPUT"
  exit $?
else
  echo "ERROR: must specify --ip or --test-fixture" >&2
  usage
fi
