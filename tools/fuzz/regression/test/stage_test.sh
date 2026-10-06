#!/usr/bin/env bash
# E71-05 tdd:
#   ci: fuzzSmokeRun_regressionCorpusDir_replaysEveryReproducer
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL $1" >&2
  exit 1
}

name=fuzzSmokeRun_regressionCorpusDir_replaysEveryReproducer
planted="$DIR/frame/zz-selftest-a.bin"
planted_b="$DIR/envelope/zz-selftest-b.bin"
dest="$(mktemp -d)"
trap 'rm -rf "$dest" "$planted" "$planted_b"' EXIT

printf 'a' > "$planted"
printf 'b' > "$planted_b"
expected=$(find "$DIR/frame" "$DIR/envelope" -type f ! -name README.md | wc -l | tr -d ' ')

count="$("$DIR/stage.sh" "$dest" frame envelope)" || fail "$name: stage.sh exited non-zero"
[ "$count" = "$expected" ] || fail "$name: staged $count of $expected reproducers"
[ -f "$dest/regression-frame-zz-selftest-a.bin" ] || fail "$name: frame reproducer missing"
[ -f "$dest/regression-envelope-zz-selftest-b.bin" ] || fail "$name: envelope reproducer missing"
echo "OK $name"

count="$("$DIR/stage.sh" "$dest" no-such-target)" || fail "stage.sh: unknown target should not fail"
[ "$count" = 0 ] || fail "stage.sh: unknown target staged files"
echo "OK stage_unknownTarget_stagesNothing"
