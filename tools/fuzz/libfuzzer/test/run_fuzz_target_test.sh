#!/usr/bin/env bash
# E15-14 tdd:
#   unit: libFuzzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer
#   unit: libFuzzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero
#
# Drives run_fuzz_target.sh against fixtures/planted_crasher.py (a fake libFuzzer-CLI target,
# never the real Swift/ASan one) so the wrapper's crash-detection and reproducer-saving logic is
# proven correct on any machine, independent of whether this toolchain can build the real target.
set -uo pipefail
shopt -s nullglob
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LIBFUZZER_DIR="$REPO_ROOT/tools/fuzz/libfuzzer"
FIXTURE="$LIBFUZZER_DIR/fixtures/planted_crasher.py"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

fail() {
  echo "FAIL $1" >&2
  exit 1
}

# --- libFuzzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer ------------------
crashing_corpus="$work/crashing-corpus"
crashing_artifacts="$work/crashing-artifacts"
mkdir -p "$crashing_corpus"
printf 'CRASH on this input' > "$crashing_corpus/planted.bin"
printf 'harmless' > "$crashing_corpus/benign.bin"

if "$LIBFUZZER_DIR/run_fuzz_target.sh" "$FIXTURE" "$crashing_corpus" "$crashing_artifacts" 300; then
  fail "libFuzzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer: wrapper exited 0"
fi
reproducer=("$crashing_artifacts"/crash-*)
[ -e "${reproducer[0]:-}" ] || fail "libFuzzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer: no reproducer saved"
grep -q "CRASH on this input" "${reproducer[0]}" \
  || fail "libFuzzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer: reproducer does not contain the crashing input"
echo "OK libFuzzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer"

# --- libFuzzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero -----------------------------
clean_corpus="$work/clean-corpus"
clean_artifacts="$work/clean-artifacts"
mkdir -p "$clean_corpus"
printf 'harmless one' > "$clean_corpus/a.bin"
printf 'harmless two' > "$clean_corpus/b.bin"

if ! "$LIBFUZZER_DIR/run_fuzz_target.sh" "$FIXTURE" "$clean_corpus" "$clean_artifacts" 300; then
  fail "libFuzzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero: wrapper exited non-zero"
fi
no_reproducer=("$clean_artifacts"/crash-*)
[ -e "${no_reproducer[0]:-}" ] && fail "libFuzzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero: unexpected reproducer saved"
echo "OK libFuzzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero"
