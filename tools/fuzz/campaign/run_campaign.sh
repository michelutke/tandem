#!/usr/bin/env bash
# E71-01 / E71-02 / E71-03: long-campaign driver for the frame length-prefix parser and Envelope decoder
# fuzz targets.
#
#   run_campaign.sh <jazzer|libfuzzer> <total-seconds> <segment-seconds> <state-dir> [frame|envelope|qr]
#
# The optional target (default frame) selects the fuzz target: frame is the frame length-prefix
# parser (E71-01), envelope the Envelope protobuf decoder (E71-02), qr the Android QR pairing
# payload parser (E71-03, jazzer only: macOS never parses QR).
#
# Fuzzes in chunks (CHUNK_SECONDS, default 1800) until <segment-seconds> of wall clock have been
# spent in this invocation or the campaign total (accumulated in <state-dir>/state.env across
# invocations) reaches <total-seconds>. A hosted runner job is capped at 6 h, so the 24 h
# campaign runs as several segments that resume from the same <state-dir> (corpus + counters).
#
#   libfuzzer: FUZZ_TARGET=<path to built -sanitize=fuzzer,address binary> (build_fuzz_target.sh);
#              every input is limited to 10 s (-timeout=10), a longer one counts as a hang.
#   jazzer:    runs FrameDecoderFuzzTest (frame), EnvelopeDecoderFuzzTest (envelope) or QrPayloadFuzzTest (qr) through tools/fuzz/jazzer/smoke.sh.
#
# <state-dir>/campaign-log.json carries duration, total execs, corpus size and crash count
# (E71-12 evidence). Exit 0: no crash so far. Exit 1: crash/hang found (reproducer in
# <state-dir>/artifacts). Exit 2: usage or setup error.
set -uo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  echo "usage: run_campaign.sh <jazzer|libfuzzer> <total-seconds> <segment-seconds> <state-dir> [frame|envelope|qr]" >&2
  exit 2
fi
ENGINE="$1"
TOTAL_SECONDS="$2"
SEGMENT_SECONDS="$3"
STATE_DIR="$4"
TARGET="${5:-frame}"
CHUNK_SECONDS="${CHUNK_SECONDS:-1800}"

for value in "$TOTAL_SECONDS" "$SEGMENT_SECONDS" "$CHUNK_SECONDS"; do
  case "$value" in
    '' | *[!0-9]*)
      echo "run_campaign.sh: seconds must be a positive integer, got '$value'" >&2
      exit 2
      ;;
  esac
done

JAZZER_MODULE="core:protocol"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
case "$TARGET" in
  frame)
    JAZZER_CLASS="dev.tandem.core.protocol.fuzz.FrameDecoderFuzzTest"
    JAZZER_METHOD="fuzzTargetFrameDecoder"
    ;;
  envelope)
    JAZZER_CLASS="dev.tandem.core.protocol.fuzz.EnvelopeDecoderFuzzTest"
    JAZZER_METHOD="fuzzTargetEnvelopeDecoder"
    ;;
  qr)
    JAZZER_CLASS="dev.tandem.core.pairing.fuzz.QrPayloadFuzzTest"
    JAZZER_METHOD="fuzzTargetQrPayloadParser"
    JAZZER_MODULE="core:pairing"
    ;;
  *)
    echo "run_campaign.sh: target must be frame, envelope or qr, got '$TARGET'" >&2
    exit 2
    ;;
esac
JAZZER_MODULE_DIR="$REPO_ROOT/android/${JAZZER_MODULE//://}"
JAZZER_CORPUS="$JAZZER_MODULE_DIR/.cifuzz-corpus/$JAZZER_CLASS/$JAZZER_METHOD"
JAZZER_RESULTS="$JAZZER_MODULE_DIR/build/test-results/testDebugUnitTest"

case "$ENGINE" in
  libfuzzer)
    if [ "$TARGET" = qr ]; then
      echo "run_campaign.sh: the qr target has no libfuzzer engine (macOS never parses QR)" >&2
      exit 2
    fi
    if [ -z "${FUZZ_TARGET:-}" ] || [ ! -x "$FUZZ_TARGET" ]; then
      echo "run_campaign.sh: FUZZ_TARGET must name an executable libFuzzer binary" >&2
      exit 2
    fi
    ;;
  jazzer) ;;
  *)
    echo "run_campaign.sh: engine must be jazzer or libfuzzer, got '$ENGINE'" >&2
    exit 2
    ;;
esac

CORPUS_DIR="$STATE_DIR/corpus"
ARTIFACT_DIR="$STATE_DIR/artifacts"
STATE_FILE="$STATE_DIR/state.env"
LOG_FILE="$STATE_DIR/campaign-log.json"
mkdir -p "$CORPUS_DIR" "$ARTIFACT_DIR"

ELAPSED=0
EXECS=0
CRASHES=0
# shellcheck disable=SC1090
[ -f "$STATE_FILE" ] && . "$STATE_FILE"

corpus_size() { find "$CORPUS_DIR" -type f | wc -l | tr -d ' '; }

write_state() {
  printf 'ELAPSED=%s\nEXECS=%s\nCRASHES=%s\n' "$ELAPSED" "$EXECS" "$CRASHES" > "$STATE_FILE"
  printf '{"engine":"%s","target":"%s","duration_seconds":%s,"total_execs":%s,"final_corpus_size":%s,"crash_count":%s}\n' \
    "$ENGINE" "$TARGET" "$ELAPSED" "$EXECS" "$(corpus_size)" "$CRASHES" > "$LOG_FILE"
}

# shellcheck disable=SC2329 # dispatched via run_${ENGINE}_chunk
run_libfuzzer_chunk() {
  local budget="$1" out="$STATE_DIR/chunk.log"
  "$FUZZ_TARGET" -max_total_time="$budget" -timeout=10 -print_final_stats=1 \
    -artifact_prefix="$ARTIFACT_DIR/" "$CORPUS_DIR" > "$out" 2>&1
  local status=$?
  EXECS=$((EXECS + $(sed -n 's/^stat::number_of_executed_units: *//p' "$out" | tail -n 1 | grep -E '^[0-9]+$' || echo 0)))
  tail -n 5 "$out"
  return "$status"
}

# shellcheck disable=SC2329 # dispatched via run_${ENGINE}_chunk
run_jazzer_chunk() {
  local budget="$1"
  mkdir -p "$JAZZER_CORPUS"
  cp -R "$CORPUS_DIR/." "$JAZZER_CORPUS/"
  JAZZER_MODULE="$JAZZER_MODULE" "$REPO_ROOT/tools/fuzz/jazzer/smoke.sh" "$JAZZER_CLASS" "$budget" "$ARTIFACT_DIR"
  local status=$?
  cp -R "$JAZZER_CORPUS/." "$CORPUS_DIR/"
  EXECS=$((EXECS + $(sed -n 's/.*stat::number_of_executed_units: *//p' "$JAZZER_RESULTS"/*.xml 2> /dev/null | tail -n 1 | grep -E '^[0-9]+$' || echo 0)))
  return "$status"
}

SEGMENT_START="$(date +%s)"
while :; do
  now="$(date +%s)"
  segment_spent=$((now - SEGMENT_START))
  remaining=$((TOTAL_SECONDS - ELAPSED))
  if [ "$remaining" -le 0 ] || [ "$segment_spent" -ge "$SEGMENT_SECONDS" ]; then
    break
  fi
  budget=$((SEGMENT_SECONDS - segment_spent))
  [ "$budget" -gt "$remaining" ] && budget="$remaining"
  [ "$budget" -gt "$CHUNK_SECONDS" ] && budget="$CHUNK_SECONDS"

  chunk_start="$(date +%s)"
  "run_${ENGINE}_chunk" "$budget"
  status=$?
  ELAPSED=$((ELAPSED + $(date +%s) - chunk_start))

  if [ "$status" -ne 0 ]; then
    CRASHES=$((CRASHES + 1))
    write_state
    echo "run_campaign.sh: $ENGINE found a crash or hang; reproducer(s) in $ARTIFACT_DIR" >&2
    exit 1
  fi
  write_state
done

write_state
echo "run_campaign.sh: $ENGINE/$TARGET ${ELAPSED}s of ${TOTAL_SECONDS}s done, crashes=$CRASHES, log=$LOG_FILE"
exit 0
