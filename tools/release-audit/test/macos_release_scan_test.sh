#!/usr/bin/env bash
# E00-30 tdd:
#   ci: macReleaseSymbolScan_tandemTestSupportTypeFixture_exitsNonZero
#   ci: macReleaseSymbolScan_currentReleaseBuild_noTestOnlySymbols
#   ci: macReleaseBundle_unexpectedExecutableOrXctest_exitsNonZero
#
# Builds the Release configuration of macos/Tandem.xcodeproj and runs
# tools/release-audit/scan-test-code.rb over `nm` output for TandemApp and TandemShare, and over
# the built Tandem.app bundle contents. Verifies the current (test-code-free) release build
# passes, then plants a temporary ManualTestClock fixture type in TandemApp.swift (kept reachable
# as an NSObject subclass so Swift's optimizer can't dead-strip it away, mirroring how a real
# TandemTestSupport type would show up if it ever leaked into the app target) and verifies the
# scan fails naming it; separately plants an extra executable and an .xctest bundle inside the
# built app bundle and verifies the bundle-contents check fails on each.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MACOS="$ROOT/macos"
SCANNER="$ROOT/tools/release-audit/scan-test-code.rb"
APP_SOURCE="$MACOS/TandemApp/TandemApp.swift"
DERIVED_DATA="$(mktemp -d)"
WORKDIR="$(mktemp -d)"

cleanup() {
  cp "$WORKDIR/TandemApp.swift.orig" "$APP_SOURCE"
  rm -rf "$DERIVED_DATA" "$WORKDIR"
}
trap cleanup EXIT
cp "$APP_SOURCE" "$WORKDIR/TandemApp.swift.orig"

build_release() {
  xcodebuild -project "$MACOS/Tandem.xcodeproj" -scheme Tandem -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" build \
    CODE_SIGNING_ALLOWED=NO -quiet
}

APP="$DERIVED_DATA/Build/Products/Release/TandemApp.app"
APP_BINARY="$APP/Contents/MacOS/TandemApp"
SHARE_BINARY="$APP/Contents/PlugIns/TandemShare.appex/Contents/MacOS/TandemShare"

# --- current release build: no test-only symbols, bundle matches the allowlist ---
build_release
[ -f "$APP_BINARY" ] || { echo "FAIL: $APP_BINARY not built" >&2; exit 1; }
[ -f "$SHARE_BINARY" ] || { echo "FAIL: $SHARE_BINARY not built" >&2; exit 1; }

nm "$APP_BINARY" > "$WORKDIR/clean-app-syms.txt"
nm "$SHARE_BINARY" > "$WORKDIR/clean-share-syms.txt"
if ! ruby "$SCANNER" text "$WORKDIR/clean-app-syms.txt" "$WORKDIR/clean-share-syms.txt" > "$WORKDIR/clean-out.txt" 2>&1; then
  echo "FAIL macReleaseSymbolScan_currentReleaseBuild_noTestOnlySymbols: scan failed on current build" >&2
  cat "$WORKDIR/clean-out.txt" >&2
  exit 1
fi
echo "OK macReleaseSymbolScan_currentReleaseBuild_noTestOnlySymbols"

if ! ruby "$SCANNER" bundle "$APP" > "$WORKDIR/clean-bundle-out.txt" 2>&1; then
  echo "FAIL: bundle check failed on current build" >&2
  cat "$WORKDIR/clean-bundle-out.txt" >&2
  exit 1
fi

# --- fixture: a planted ManualTestClock type must be caught by name ---
# An NSObject subclass always emits a real Objective-C class symbol, so it survives Release
# optimization the way a plain unused Swift function or string literal would not. init() calls it
# so the reference itself can't be optimized away either.
cat > "$APP_SOURCE" <<'SWIFT'
import SwiftUI

final class ManualTestClockScanFixture: NSObject {
    // Never shipped: exists only to prove the release scan catches a TandemTestSupport type by
    // name.
}

@main
struct TandemMenuBarApp: App {
    // E22-05's SettingsComposition.swift extends this type from a separate, always-compiled
    // (not #if DEBUG-only) file and reads this property -- this stub swaps out the real
    // TandemApp.swift wholesale, so it must keep re-declaring anything another file in this
    // target still references, or this fixture build fails to compile with an unrelated
    // "cannot find in scope" error instead of exercising what this test actually checks.
    nonisolated(unsafe) private(set) static var retainedProductionLifecycle: AppComposition.RetainedLifecycle?

    init() {
        _ = ManualTestClockScanFixture()
    }

    var body: some Scene {
        MenuBarExtra("Tandem", systemImage: "circle.fill") {
            Text("Tandem")
        }
    }
}
SWIFT

build_release
nm "$APP_BINARY" > "$WORKDIR/fixture-app-syms.txt"
if out="$(ruby "$SCANNER" text "$WORKDIR/fixture-app-syms.txt" 2>&1)"; then
  echo "FAIL macReleaseSymbolScan_tandemTestSupportTypeFixture_exitsNonZero: scan passed with fixture present" >&2
  exit 1
fi
grep -q "ManualTestClock" <<<"$out" || { echo "FAIL: scan failed without naming ManualTestClock" >&2; echo "$out" >&2; exit 1; }
echo "OK macReleaseSymbolScan_tandemTestSupportTypeFixture_exitsNonZero"

cp "$WORKDIR/TandemApp.swift.orig" "$APP_SOURCE"

# --- bundle fixture: an extra executable or .xctest bundle must fail the bundle-contents check ---
printf '\xcf\xfa\xed\xfe' > "$APP/Contents/Resources/rogue-helper"
if out="$(ruby "$SCANNER" bundle "$APP" 2>&1)"; then
  echo "FAIL macReleaseBundle_unexpectedExecutableOrXctest_exitsNonZero: scan passed with a rogue executable present" >&2
  exit 1
fi
grep -q "unexpected executable" <<<"$out" || { echo "FAIL: bundle scan failed without naming the rogue executable" >&2; echo "$out" >&2; exit 1; }
rm -f "$APP/Contents/Resources/rogue-helper"

mkdir -p "$APP/Contents/PlugIns/Rogue.xctest/Contents/MacOS"
printf '\xcf\xfa\xed\xfe' > "$APP/Contents/PlugIns/Rogue.xctest/Contents/MacOS/Rogue"
if out="$(ruby "$SCANNER" bundle "$APP" 2>&1)"; then
  echo "FAIL macReleaseBundle_unexpectedExecutableOrXctest_exitsNonZero: scan passed with a rogue .xctest bundle present" >&2
  exit 1
fi
grep -q "\.xctest" <<<"$out" || { echo "FAIL: bundle scan failed without naming the rogue .xctest bundle" >&2; echo "$out" >&2; exit 1; }
rm -rf "$APP/Contents/PlugIns/Rogue.xctest"
echo "OK macReleaseBundle_unexpectedExecutableOrXctest_exitsNonZero"
