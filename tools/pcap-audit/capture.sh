#!/usr/bin/env bash
# tools/pcap-audit/capture.sh — E15-04: tshark capture filtered to the configured Tandem port(s)
# for the duration of a scripted session or a fixed timeout.
#
# Usage:
#   capture.sh --port <port> --out <file.pcapng> [--iface <iface>] --duration <seconds>
#   capture.sh --port <port> --out <file.pcapng> [--iface <iface>] --script -- <command...>
#
# --duration runs the capture for a fixed number of seconds.
# --script starts the capture, runs <command...> to completion, then stops the capture; the
#   command's exit status is capture.sh's exit status. Everything after `--script --` is passed
#   through verbatim as the command to run.
#
# The capture filter is always "tcp port <port>" on <iface> (default lo0), so only that port's
# frames are ever written to <out>, regardless of what else is happening on the interface.
set -euo pipefail

TSHARK="${TSHARK_BIN:-tshark}"
IFACE="lo0"
PORT=""
OUT=""
DURATION=""
SCRIPT_CMD=()

usage() {
  cat <<'EOF'
Usage: capture.sh --port <port> --out <file.pcapng> [--iface <iface>] (--duration <seconds> | --script -- <command...>)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --out)
      OUT="$2"
      shift 2
      ;;
    --iface)
      IFACE="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --script)
      shift
      if [[ "${1:-}" != "--" ]]; then
        echo "capture.sh: --script must be followed by --" >&2
        usage >&2
        exit 2
      fi
      shift
      SCRIPT_CMD=("$@")
      break
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "capture.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PORT" || -z "$OUT" ]]; then
  echo "capture.sh: --port and --out are required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$DURATION" && ${#SCRIPT_CMD[@]} -eq 0 ]]; then
  echo "capture.sh: exactly one of --duration or --script is required" >&2
  usage >&2
  exit 2
fi

if [[ -n "$DURATION" && ${#SCRIPT_CMD[@]} -gt 0 ]]; then
  echo "capture.sh: --duration and --script are mutually exclusive" >&2
  usage >&2
  exit 2
fi

FILTER="tcp port ${PORT}"

if [[ ${#SCRIPT_CMD[@]} -gt 0 ]]; then
  tshark_log="$(mktemp)"
  "$TSHARK" -i "$IFACE" -f "$FILTER" -w "$OUT" 2>"$tshark_log" &
  tshark_pid=$!

  # Wait (up to 15 s) until tshark reports it is capturing, so a loaded machine cannot race the
  # scripted session ahead of the capture; then a short settle for the BPF filter to apply.
  for _ in $(seq 1 150); do
    grep -q "Capturing on" "$tshark_log" 2>/dev/null && break
    kill -0 "$tshark_pid" 2>/dev/null || break
    sleep 0.1
  done
  sleep 0.5

  set +e
  "${SCRIPT_CMD[@]}"
  script_status=$?
  set -e

  # Let the last frames (e.g. a closing FIN) land before tshark is stopped.
  sleep 1

  kill -INT "$tshark_pid" 2>/dev/null || true
  wait "$tshark_pid" 2>/dev/null || true
  rm -f "$tshark_log"

  exit "$script_status"
else
  "$TSHARK" -i "$IFACE" -f "$FILTER" -w "$OUT" -a "duration:${DURATION}"
fi
