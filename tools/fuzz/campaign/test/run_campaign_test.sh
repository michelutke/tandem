#!/usr/bin/env bash
# E71-13 tdd:
#   unit: fuzzCampaignRunner_domainTarget_logsMessage
#   unit: fuzzCampaignRunner_domainTargetWithoutMessage_exitsTwo
#   unit: fuzzCampaignRunner_domainTargetWithJazzer_exitsTwo
# E71-03 tdd:
#   unit: fuzzCampaignRunner_qrTargetWithLibfuzzer_exitsTwo
# E71-02 tdd:
#   unit: fuzzCampaignRunner_envelopeTarget_logsTarget
#   unit: fuzzCampaignRunner_unknownTarget_exitsTwo
# E71-01 tdd:
#   unit: fuzzCampaignRunner_plantedCrashingTarget_exitsNonZeroWithReproducerAndCrashCount
#   unit: fuzzCampaignRunner_cleanTarget_exitsZeroAndLogsDurationExecsCorpusCrashes
#   unit: fuzzCampaignRunner_secondSegment_resumesElapsedAndCorpus
#
# Drives run_campaign.sh against the libFuzzer planted-crasher fixture (never the real target).
set -uo pipefail
shopt -s nullglob
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
RUNNER="$REPO_ROOT/tools/fuzz/campaign/run_campaign.sh"
export FUZZ_TARGET="$REPO_ROOT/tools/fuzz/libfuzzer/fixtures/planted_crasher.py"
export CHUNK_SECONDS=1

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

fail() {
  echo "FAIL $1" >&2
  exit 1
}

# --- plantedCrashingTarget ------------------------------------------------------------------
crash_state="$work/crash"
mkdir -p "$crash_state/corpus"
printf 'CRASH on this input' > "$crash_state/corpus/planted.bin"
name=fuzzCampaignRunner_plantedCrashingTarget_exitsNonZeroWithReproducerAndCrashCount
"$RUNNER" libfuzzer 5 5 "$crash_state" > /dev/null 2>&1 && fail "$name: exited 0"
reproducer=("$crash_state"/artifacts/crash-*)
[ -e "${reproducer[0]:-}" ] || fail "$name: no reproducer saved"
grep -q '"crash_count":1' "$crash_state/campaign-log.json" || fail "$name: crash_count not 1"
echo "OK $name"

# --- cleanTarget ----------------------------------------------------------------------------
clean_state="$work/clean"
mkdir -p "$clean_state/corpus"
printf 'harmless' > "$clean_state/corpus/a.bin"
name=fuzzCampaignRunner_cleanTarget_exitsZeroAndLogsDurationExecsCorpusCrashes
"$RUNNER" libfuzzer 2 2 "$clean_state" > /dev/null 2>&1 || fail "$name: exited non-zero"
for key in duration_seconds total_execs final_corpus_size crash_count; do
  grep -q "\"$key\":" "$clean_state/campaign-log.json" || fail "$name: log lacks $key"
done
grep -q '"crash_count":0' "$clean_state/campaign-log.json" || fail "$name: crash_count not 0"
grep -q '"final_corpus_size":1' "$clean_state/campaign-log.json" || fail "$name: corpus size not 1"
echo "OK $name"

# --- secondSegment --------------------------------------------------------------------------
name=fuzzCampaignRunner_secondSegment_resumesElapsedAndCorpus
"$RUNNER" libfuzzer 2 2 "$clean_state" > /dev/null 2>&1 || fail "$name: resumed run exited non-zero"
grep -q '^ELAPSED=[2-9]' "$clean_state/state.env" || fail "$name: elapsed not retained"
grep -q '"final_corpus_size":1' "$clean_state/campaign-log.json" || fail "$name: corpus lost"
echo "OK $name"

# --- envelopeTarget -------------------------------------------------------------------------
env_state="$work/envelope"
mkdir -p "$env_state/corpus"
printf 'harmless' > "$env_state/corpus/a.bin"
name=fuzzCampaignRunner_envelopeTarget_logsTarget
"$RUNNER" libfuzzer 2 2 "$env_state" envelope > /dev/null 2>&1 || fail "$name: exited non-zero"
grep -q '"target":"envelope"' "$env_state/campaign-log.json" || fail "$name: target not logged"
echo "OK $name"

# --- unknownTarget --------------------------------------------------------------------------
name=fuzzCampaignRunner_unknownTarget_exitsTwo
"$RUNNER" libfuzzer 2 2 "$work/unknown" bogus > /dev/null 2>&1
[ "$?" -eq 2 ] || fail "$name: did not exit 2"
echo "OK $name"

# --- qrTargetWithLibfuzzer ------------------------------------------------------------------
name=fuzzCampaignRunner_qrTargetWithLibfuzzer_exitsTwo
"$RUNNER" libfuzzer 2 2 "$work/qr" qr > /dev/null 2>&1
[ "$?" -eq 2 ] || fail "$name: did not exit 2"
echo "OK $name"

# --- domainTarget ---------------------------------------------------------------------------
domain_state="$work/domain"
mkdir -p "$domain_state/corpus"
printf 'harmless' > "$domain_state/corpus/a.bin"
name=fuzzCampaignRunner_domainTarget_logsMessage
MESSAGE=media_control "$RUNNER" libfuzzer 2 2 "$domain_state" domain > /dev/null 2>&1 || fail "$name: exited non-zero"
grep -q '"target":"domain","message":"media_control"' "$domain_state/campaign-log.json" || fail "$name: message not logged"
echo "OK $name"

name=fuzzCampaignRunner_domainTargetWithoutMessage_exitsTwo
"$RUNNER" libfuzzer 2 2 "$work/domain-nomsg" domain > /dev/null 2>&1
[ "$?" -eq 2 ] || fail "$name: did not exit 2"
echo "OK $name"

name=fuzzCampaignRunner_domainTargetWithJazzer_exitsTwo
MESSAGE=media "$RUNNER" jazzer 2 2 "$work/domain-jazzer" domain > /dev/null 2>&1
[ "$?" -eq 2 ] || fail "$name: did not exit 2"
echo "OK $name"
