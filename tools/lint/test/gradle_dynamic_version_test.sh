#!/usr/bin/env bash
# E00-29 tdd:
#   ci: gradleVersions_dynamicVersionFixture_checkFails
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
NOTIFICATIONS_BUILD="$ANDROID/feature/notifications/build.gradle.kts"
BACKUP="$(mktemp)"
cp "$NOTIFICATIONS_BUILD" "$BACKUP"
cd "$ANDROID"

restore() {
  cp "$BACKUP" "$NOTIFICATIONS_BUILD"
  rm -f "$BACKUP"
}
trap restore EXIT

run_expect_verify_module_rules_failure() {
  local test_name="$1"
  local expect_grep="$2"

  if out="$(./gradlew -q verifyModuleRules 2>&1)"; then
    echo "FAIL $test_name: build passed" >&2
    exit 1
  fi
  grep -q "verifyModuleRules" <<<"$out" || { echo "FAIL $test_name: build failed without verifyModuleRules" >&2; echo "$out" >&2; exit 1; }
  grep -q "$expect_grep" <<<"$out" || { echo "FAIL $test_name: expected message not found" >&2; echo "$out" >&2; exit 1; }
  echo "OK $test_name"
}

cat >> "$NOTIFICATIONS_BUILD" <<'KTS'

dependencies {
    implementation("com.squareup.okio:okio:+")
}
KTS
run_expect_verify_module_rules_failure \
  "gradleVersions_dynamicVersionFixture_checkFails" \
  "uses dynamic version '+' (exact versions only)"
