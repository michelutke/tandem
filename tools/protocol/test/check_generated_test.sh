#!/usr/bin/env bash
# E00-10 tdd:
#   ci: generatedCodeCheck_handEditedPbKtFile_jobFailsShowingDiff
#   ci: generatedCodeCheck_handEditedPbSwiftFile_jobFailsShowingDiff
#   ci: generatedCodeCheck_protoChangedAndRegenerated_jobPasses
# Each scenario runs the real check against a scratch git repo holding a copy of the protocol
# sources and generated code (needs buf and network access for the pinned remote plugins).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PATHS=(tools/protocol protocol android/core/protocol/src/main macos/Packages/TandemProtocol/Sources/TandemProtocol)
KT=android/core/protocol/src/main/kotlin/dev/tandem/protocol/v1/PlaceholderKt.kt
SWIFT=macos/Packages/TandemProtocol/Sources/TandemProtocol/tandem/v1/placeholder.pb.swift

scratch() {
  local dir; dir="$(mktemp -d)"
  (cd "$REPO_ROOT" && tar cf - "${PATHS[@]}") | (cd "$dir" && tar xf -)
  (cd "$dir" && git init -q && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base)
  echo "$dir"
}
commit_all() { (cd "$1" && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm edit); }
expect_fail() {
  local name="$1" dir="$2" out
  if out="$("$dir/tools/protocol/check_generated.sh" "$dir" 2>&1)"; then echo "FAIL $name: check passed" >&2; exit 1; fi
  grep -q "^diff --git" <<<"$out" || { echo "FAIL $name: no diff shown" >&2; echo "$out" >&2; exit 1; }
  echo "OK $name"
}

d="$(scratch)"; echo "// hand edit" >> "$d/$KT"; commit_all "$d"
expect_fail generatedCodeCheck_handEditedPbKtFile_jobFailsShowingDiff "$d"; rm -rf "$d"

d="$(scratch)"; echo "// hand edit" >> "$d/$SWIFT"; commit_all "$d"
expect_fail generatedCodeCheck_handEditedPbSwiftFile_jobFailsShowingDiff "$d"; rm -rf "$d"

d="$(scratch)"
sed -i.bak 's/string value = 1;/string value = 1;\n  string note = 2;/' "$d/protocol/proto/tandem/v1/placeholder.proto" && rm "$d/protocol/proto/tandem/v1/placeholder.proto.bak"
"$d/tools/protocol/generate.sh" >/dev/null
(cd "$d" && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm regen)
"$d/tools/protocol/check_generated.sh" "$d" >/dev/null
echo "OK generatedCodeCheck_protoChangedAndRegenerated_jobPasses"; rm -rf "$d"
