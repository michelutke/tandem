#!/usr/bin/env bash
# E00-05 tdd:
#   ci: ktlintCheck_wildcardImportFixture_exitsNonZero
#   ci: ktlintAndDetekt_emptySkeleton_exitZero
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
FIXTURE="$ANDROID/core/testing/src/test/kotlin/dev/tandem/core/testing/WildcardImportFixture.kt"
trap 'rm -f "$FIXTURE"' EXIT
cd "$ANDROID"

./gradlew -q ktlintCheck detekt
echo "OK ktlintAndDetekt_emptySkeleton_exitZero"

cat > "$FIXTURE" <<'KT'
package dev.tandem.core.testing

import kotlinx.coroutines.flow.*

internal val wildcardFixture = emptyFlow<Int>()
KT
if ./gradlew -q :core:testing:ktlintTestSourceSetCheck >/dev/null 2>&1; then
  echo "FAIL ktlintCheck_wildcardImportFixture_exitsNonZero: ktlint accepted a wildcard import" >&2
  exit 1
fi
echo "OK ktlintCheck_wildcardImportFixture_exitsNonZero"
