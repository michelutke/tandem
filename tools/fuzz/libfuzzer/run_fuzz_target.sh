#!/usr/bin/env bash
# E15-14: runs any libFuzzer-CLI-compatible executable against a seed corpus, in two stages:
#
#   1. seed corpus replay (`-runs=0`): executes every corpus file exactly once, no mutation.
#      Exit non-zero on any crash — this is the PR-gating "0 crashes on the known corpus" check.
#   2. budgeted fuzzing (`-max_total_time=<budget>`): lets the target mutate for up to <budget>
#      seconds. Exit 0 if the budget is exhausted without a crash (a timeout alone is not a
#      failure) or non-zero if it crashes, printing the saved reproducer's path either way.
#
# Generic on purpose: both `smoke.sh` (the real Swift/ASan target) and
# test/run_fuzz_target_test.sh (the planted-crasher fixture, fixtures/planted_crasher.py) drive
# this same script, so the crash-detection logic is proven correct independently of whether the
# real target can be built on this machine (see README.md).
#
#   run_fuzz_target.sh <target-executable> <corpus-dir> <artifact-dir> <budget-seconds>
set -uo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: run_fuzz_target.sh <target-executable> <corpus-dir> <artifact-dir> <budget-seconds>" >&2
  exit 2
fi
target="$1"
corpus_dir="$2"
artifact_dir="$3"
budget="$4"

mkdir -p "$artifact_dir"

latest_reproducer() {
  ls -t "$artifact_dir"/crash-* 2>/dev/null | head -1
}

echo "== seed corpus replay (0 crashes expected): $corpus_dir =="
shopt -s nullglob
corpus_files=("$corpus_dir"/*)
shopt -u nullglob
if [ "${#corpus_files[@]}" -eq 0 ]; then
  echo "run_fuzz_target.sh: corpus dir $corpus_dir is empty" >&2
  exit 1
fi
if ! "$target" -runs=0 -artifact_prefix="$artifact_dir/" "${corpus_files[@]}"; then
  reproducer="$(latest_reproducer)"
  echo "seed corpus replay crashed; reproducer: ${reproducer:-<none saved>}" >&2
  exit 1
fi
echo "seed corpus replay: 0 crashes"

echo "== fuzzing for up to ${budget}s =="
if "$target" -max_total_time="$budget" -artifact_prefix="$artifact_dir/" "$corpus_dir"; then
  echo "fuzzing budget exhausted with no crash"
  exit 0
fi
reproducer="$(latest_reproducer)"
echo "fuzz target crashed; reproducer: ${reproducer:-<none saved>}" >&2
exit 1
