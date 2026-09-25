#!/usr/bin/env bash
# E00-29 tdd:
#   ci: gradleDependencyVerification_tamperedArtifactChecksum_buildFails
#   ci: gradleDependencyVerification_newDependencyWithoutMetadata_buildFails
#
# Exercises Gradle's dependency verification (android/gradle/verification-metadata.xml,
# verify-metadata=true) end to end against a throwaway local Maven repository, so the test
# never touches the real repo's metadata and never needs network access. Each run uses a
# never-before-resolved fake dependency version so Gradle cannot serve it from a cache that
# was already verified in an earlier build (Gradle only verifies an artifact the first time
# it is downloaded into the module cache).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID="$REPO_ROOT/android"
FIXTURE="$REPO_ROOT/tools/lint/fixtures/gradle-verification"
METADATA="$FIXTURE/gradle/verification-metadata.xml"
RUN_ID="$$-$RANDOM"

cleanup() {
  rm -rf "$FIXTURE/repo" "$FIXTURE/gradle"
}
trap cleanup EXIT

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

make_artifact() {
  local version="$1"
  local dir="$FIXTURE/repo/dev/tandem/fixture/verify-target/$version"
  mkdir -p "$dir"
  printf 'gradle-dependency-verification fixture artifact %s\n' "$version" > "$dir/verify-target-$version.jar"
  cat > "$dir/verify-target-$version.pom" <<POM
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>dev.tandem.fixture</groupId>
  <artifactId>verify-target</artifactId>
  <version>$version</version>
</project>
POM
  echo "$dir"
}

# jar_sha empty means: omit the component from verification-metadata.xml entirely (simulates a
# dependency added without an entry).
write_metadata() {
  local version="$1" jar_sha="$2" pom_sha="$3"
  mkdir -p "$(dirname "$METADATA")"
  if [ -z "$jar_sha" ]; then
    cat > "$METADATA" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<verification-metadata xmlns="https://schema.gradle.org/dependency-verification">
   <configuration>
      <verify-metadata>true</verify-metadata>
      <verify-signatures>false</verify-signatures>
   </configuration>
   <components/>
</verification-metadata>
XML
    return
  fi
  cat > "$METADATA" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<verification-metadata xmlns="https://schema.gradle.org/dependency-verification">
   <configuration>
      <verify-metadata>true</verify-metadata>
      <verify-signatures>false</verify-signatures>
   </configuration>
   <components>
      <component group="dev.tandem.fixture" name="verify-target" version="$version">
         <artifact name="verify-target-$version.jar">
            <sha256 value="$jar_sha" origin="test fixture"/>
         </artifact>
         <artifact name="verify-target-$version.pom">
            <sha256 value="$pom_sha" origin="test fixture"/>
         </artifact>
      </component>
   </components>
</verification-metadata>
XML
}

run_fixture() {
  local version="$1"
  (cd "$FIXTURE" && "$ANDROID/gradlew" -q "-PfixtureVersion=$version" resolveFixture)
}

# --- Test 1: a tampered artifact checksum fails the build. ---
V1="0.0.1-tampered-$RUN_ID"
DIR1="$(make_artifact "$V1")"
JAR_SHA="$(sha256_of "$DIR1/verify-target-$V1.jar")"
POM_SHA="$(sha256_of "$DIR1/verify-target-$V1.pom")"
BAD_SHA="${JAR_SHA%??}00"
[ "$BAD_SHA" != "$JAR_SHA" ] || { echo "fixture setup error: mutated checksum equals the real one" >&2; exit 1; }

write_metadata "$V1" "$BAD_SHA" "$POM_SHA"
if out="$(run_fixture "$V1" 2>&1)"; then
  echo "FAIL gradleDependencyVerification_tamperedArtifactChecksum_buildFails: build passed" >&2
  echo "$out" >&2
  exit 1
fi
grep -qi "dependency verification" <<<"$out" || {
  echo "FAIL gradleDependencyVerification_tamperedArtifactChecksum_buildFails: no verification error" >&2
  echo "$out" >&2
  exit 1
}
grep -q "verify-target" <<<"$out" || {
  echo "FAIL gradleDependencyVerification_tamperedArtifactChecksum_buildFails: error doesn't name the artifact" >&2
  echo "$out" >&2
  exit 1
}
echo "OK gradleDependencyVerification_tamperedArtifactChecksum_buildFails"

# Sanity check: the same fixture with the real checksum passes (proves the failure above was the
# tampered checksum, not a fixture-setup mistake).
write_metadata "$V1" "$JAR_SHA" "$POM_SHA"
if ! out="$(run_fixture "$V1" 2>&1)"; then
  echo "FAIL gradleDependencyVerification sanity check: fixture with the real checksum should pass" >&2
  echo "$out" >&2
  exit 1
fi
echo "OK gradleDependencyVerification sanity check (correct checksum passes)"

# --- Test 2: a dependency with no verification-metadata entry at all fails the build. ---
V2="0.0.1-missing-$RUN_ID"
make_artifact "$V2" >/dev/null
write_metadata "$V2" "" ""
if out="$(run_fixture "$V2" 2>&1)"; then
  echo "FAIL gradleDependencyVerification_newDependencyWithoutMetadata_buildFails: build passed" >&2
  echo "$out" >&2
  exit 1
fi
grep -qi "dependency verification" <<<"$out" || {
  echo "FAIL gradleDependencyVerification_newDependencyWithoutMetadata_buildFails: no verification error" >&2
  echo "$out" >&2
  exit 1
}
grep -q "verify-target" <<<"$out" || {
  echo "FAIL gradleDependencyVerification_newDependencyWithoutMetadata_buildFails: error doesn't name the artifact" >&2
  echo "$out" >&2
  exit 1
}
echo "OK gradleDependencyVerification_newDependencyWithoutMetadata_buildFails"
