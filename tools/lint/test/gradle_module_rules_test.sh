#!/usr/bin/env bash
# E00-14 tdd:
#   ci: moduleDependencyRule_featureDependsOnFeatureFixture_buildFails
#   ci: dependencyDenylist_nanoHttpdAdded_buildFails
#   ci: dependencyDenylist_crashlyticsAdded_buildFails
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
CLIPBOARD_BUILD="$ANDROID/feature/clipboard/build.gradle.kts"
NOTIFICATIONS_BUILD="$ANDROID/feature/notifications/build.gradle.kts"
CLIPBOARD_BACKUP="$(mktemp)"
NOTIFICATIONS_BACKUP="$(mktemp)"
cp "$CLIPBOARD_BUILD" "$CLIPBOARD_BACKUP"
cp "$NOTIFICATIONS_BUILD" "$NOTIFICATIONS_BACKUP"
cd "$ANDROID"

restore() {
  cp "$CLIPBOARD_BACKUP" "$CLIPBOARD_BUILD"
  cp "$NOTIFICATIONS_BACKUP" "$NOTIFICATIONS_BUILD"
}
trap 'restore; rm -f "$CLIPBOARD_BACKUP" "$NOTIFICATIONS_BACKUP"' EXIT

run_expect_verify_module_rules_failure() {
  local test_name="$1"
  local target="$2"
  local expect_grep="$3"

  if out="$(./gradlew -q "$target" 2>&1)"; then
    echo "FAIL $test_name: build passed" >&2
    exit 1
  fi
  grep -q "verifyModuleRules" <<<"$out" || { echo "FAIL $test_name: build failed without verifyModuleRules" >&2; echo "$out" >&2; exit 1; }
  grep -q "$expect_grep" <<<"$out" || { echo "FAIL $test_name: expected message not found" >&2; echo "$out" >&2; exit 1; }
  echo "OK $test_name"
}

cat >> "$CLIPBOARD_BUILD" <<'KTS'

dependencies {
    implementation(project(":feature:files"))
}
KTS
run_expect_verify_module_rules_failure \
  "moduleDependencyRule_featureDependsOnFeatureFixture_buildFails" \
  ":feature:clipboard:check" \
  "feature:clipboard: feature module depends on feature module :feature:files"
restore

cat >> "$NOTIFICATIONS_BUILD" <<'KTS'

dependencies {
    implementation("org.nanohttpd:nanohttpd:2.3.1")
}
KTS
run_expect_verify_module_rules_failure \
  "dependencyDenylist_nanoHttpdAdded_buildFails" \
  ":feature:notifications:check" \
  "matches denylisted pattern 'nanohttpd'"
restore

cat >> "$NOTIFICATIONS_BUILD" <<'KTS'

dependencies {
    implementation("com.google.firebase:firebase-crashlytics:19.4.4")
}
KTS
run_expect_verify_module_rules_failure \
  "dependencyDenylist_crashlyticsAdded_buildFails" \
  ":feature:notifications:check" \
  "matches denylisted pattern 'firebase'"
restore
