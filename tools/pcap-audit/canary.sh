#!/usr/bin/env bash
# tools/pcap-audit/canary.sh — E15-07: automates the PRD test-strategy canary procedure.
#
# Generates a fresh `TANDEM-CANARY-<random>` (128 random bits, so two runs never reuse a canary),
# then runs the enabled injection steps in order:
#
#   1. phase1 (display-name): automated everywhere. The E15-15 JVM harness client's production
#      `DeviceInfoProvider` is fed the canary as `--display-name`, pairs with the real Mac app, and
#      restart-reconnects, all inside one whole-interface tshark capture that is then scanned by
#      canary_scan.py (tools/harness/integration/e15-07-canary-phase1.sh). There is no test-only
#      wire payload, debug channel, or debug flag for canary injection (backlog E15-07 notes,
#      cycle 2 decision) — the canary only ever rides `PairRequest.deviceInfo.displayName` during a
#      genuine pairing, the same production path a real display name takes.
#   2. notification (E30): posts the canary through the companion app (E00-22) via
#      `adb shell am broadcast -a dev.tandem.companion.POST --es kind canary --es nonce <nonce>`;
#      Tandem filters its own notifications, so the companion app is required.
#   3. clipboard (E31-06): fires the share-target `SEND` intent with the canary as clipboard text.
#   4. mirror (E61-09): starts the companion InputCounterActivity and types the canary into its
#      focused text field with `adb shell input text`, so the canary is on the phone screen while a
#      mirror session streams it. The capture window around this step must also contain >= 1 MB of
#      media-connection traffic (media_volume.py), so a zero-occurrence result is not vacuous.
#   5. file (E40-11): would fire a `SEND` intent with the canary as file content; E40-11 (file
#      share target, Phase 4) isn't built yet, so this step stays disabled until it lands.
#
# Steps 2-4 need a live phone with adb attached (and, for a real run, paired with a Mac) — they are
# not runnable in CI; `--dry-run` prints their exact commands without touching any device, which is
# what this script's own unit tests exercise. The live-phone capture/scan for steps 2-4 is done by
# wrapping a real (non-dry-run) invocation of this script in tools/pcap-audit/capture.sh, per the
# manual gate procedure in docs/testing/manual-gates.md (E00-23) — canary.sh itself only fires the
# injection command for those steps.
#
# Each later-phase step (2-4) is gated by a flag naming its owning feature issue. Once that issue
# is done, the step can no longer be turned off — `--disable-<issue>` on an already-shipped feature
# exits non-zero (fails, not skips), so a canary run can never silently stop covering a feature that
# has landed. E40-11 is not done yet, so `--enable-e40-11` (attempting to force the file step on
# before its feature exists) also exits non-zero.
#
# Usage:
#   canary.sh --dry-run [--phase1-only] [--disable-e30] [--disable-e31-06] [--enable-e40-11]
#   canary.sh [--phase1-only] [--disable-e30] [--disable-e31-06] [--enable-e40-11] [--out-dir <dir>]
#
# --phase1-only runs (or plans) only the phase1 step — the mode used for an automated/CI run, which
# has no Android device to drive the notification/clipboard/file steps at all. It is not a
# "disable": it does not require any owning feature issue to be undone, so it never triggers the
# fail-not-skip rule above.
set -euo pipefail

CANARY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE1_SCRIPT="$CANARY_ROOT/tools/harness/integration/e15-07-canary-phase1.sh"

# Feature gates: flip to true only once the owning issue has actually merged. These decide whether
# `--disable-<issue>` is even legal (acceptance: "once done, running with the step disabled exits
# non-zero").
readonly E30_NOTIFICATION_DONE=true   # E30 notifications + E00-22 companion app: shipped.
readonly E31_06_CLIPBOARD_DONE=true   # E31-06 share target: shipped.
readonly E61_09_MIRROR_DONE=true      # E61-09 mirror canary: this step.
readonly E40_11_FILE_DONE=false       # E40-11 file share target (Phase 4): not built yet.

DRY_RUN=false
PHASE1_ONLY=false
DISABLE_E30=false
DISABLE_E31_06=false
DISABLE_E61_09=false
ENABLE_E40_11=false
OUT_DIR=""

usage() {
  cat <<'EOF'
Usage: canary.sh [--dry-run] [--phase1-only] [--disable-e30] [--disable-e31-06] [--disable-e61-09] [--enable-e40-11] [--out-dir <dir>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --phase1-only) PHASE1_ONLY=true; shift ;;
    --disable-e30) DISABLE_E30=true; shift ;;
    --disable-e31-06) DISABLE_E31_06=true; shift ;;
    --disable-e61-09) DISABLE_E61_09=true; shift ;;
    --enable-e40-11) ENABLE_E40_11=true; shift ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "canary.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$DISABLE_E30" == true && "$E30_NOTIFICATION_DONE" == true && "$PHASE1_ONLY" != true ]]; then
  echo "canary.sh: --disable-e30 refused -- E30 (notifications) is done, a canary run may no longer skip it" >&2
  exit 1
fi
if [[ "$DISABLE_E31_06" == true && "$E31_06_CLIPBOARD_DONE" == true && "$PHASE1_ONLY" != true ]]; then
  echo "canary.sh: --disable-e31-06 refused -- E31-06 (share target) is done, a canary run may no longer skip it" >&2
  exit 1
fi
if [[ "$DISABLE_E61_09" == true && "$E61_09_MIRROR_DONE" == true && "$PHASE1_ONLY" != true ]]; then
  echo "canary.sh: --disable-e61-09 refused -- E61-09 (mirror canary) is done, a canary run may no longer skip it" >&2
  exit 1
fi
if [[ "$ENABLE_E40_11" == true && "$E40_11_FILE_DONE" != true ]]; then
  echo "canary.sh: --enable-e40-11 refused -- E40-11 (file share target) is not done, the feature does not exist yet" >&2
  exit 1
fi

NOTIFICATION_ENABLED=$([[ "$PHASE1_ONLY" == true || "$DISABLE_E30" == true ]] && echo false || echo true)
CLIPBOARD_ENABLED=$([[ "$PHASE1_ONLY" == true || "$DISABLE_E31_06" == true ]] && echo false || echo true)
MIRROR_ENABLED=$([[ "$PHASE1_ONLY" == true || "$DISABLE_E61_09" == true ]] && echo false || echo true)
FILE_ENABLED=$([[ "$PHASE1_ONLY" != true && "$ENABLE_E40_11" == true ]] && echo true || echo false)

NONCE="$(openssl rand -hex 16)"
CANARY="TANDEM-CANARY-${NONCE}"

SHARE_TARGET_COMPONENT="dev.tandem/dev.tandem.feature.clipboard.ShareTargetActivity"
MIRROR_CANARY_ACTIVITY="dev.tandem.companion/.InputCounterActivity"

phase1_cmd() {
  local out_pcap="$1"
  printf '%s %s %s' "$PHASE1_SCRIPT" "$CANARY" "$out_pcap"
}

notification_cmd() {
  printf 'adb shell am broadcast -a dev.tandem.companion.POST --es kind canary --es nonce %s' "$NONCE"
}

clipboard_cmd() {
  printf 'adb shell am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "%s" -n %s' \
    "$CANARY" "$SHARE_TARGET_COMPONENT"
}

mirror_display_cmd() {
  printf 'adb shell am start -n %s' "$MIRROR_CANARY_ACTIVITY"
}

mirror_type_cmd() {
  printf 'adb shell input text %s' "$CANARY"
}

echo "CANARY: $CANARY"
echo "NONCE: $NONCE"

if [[ "$DRY_RUN" == true ]]; then
  OUT_DIR="${OUT_DIR:-<out-dir>}"

  echo "STEP phase1 enabled"
  echo "CMD $(phase1_cmd "$OUT_DIR/phase1.pcapng")"

  if [[ "$NOTIFICATION_ENABLED" == true ]]; then
    echo "STEP notification enabled"
    echo "CMD $(notification_cmd)"
  elif [[ "$PHASE1_ONLY" == true ]]; then
    echo "STEP notification skipped (--phase1-only)"
  else
    echo "STEP notification skipped (--disable-e30)"
  fi

  if [[ "$CLIPBOARD_ENABLED" == true ]]; then
    echo "STEP clipboard enabled"
    echo "CMD $(clipboard_cmd)"
  elif [[ "$PHASE1_ONLY" == true ]]; then
    echo "STEP clipboard skipped (--phase1-only)"
  else
    echo "STEP clipboard skipped (--disable-e31-06)"
  fi

  if [[ "$MIRROR_ENABLED" == true ]]; then
    echo "STEP mirror enabled"
    echo "CMD $(mirror_display_cmd)"
    echo "CMD $(mirror_type_cmd)"
  elif [[ "$PHASE1_ONLY" == true ]]; then
    echo "STEP mirror skipped (--phase1-only)"
  else
    echo "STEP mirror skipped (--disable-e61-09)"
  fi

  if [[ "$FILE_ENABLED" == true ]]; then
    echo "STEP file enabled"
  elif [[ "$PHASE1_ONLY" == true ]]; then
    echo "STEP file skipped (--phase1-only)"
  else
    echo "STEP file skipped (E40-11 not done)"
  fi

  exit 0
fi

OUT_DIR="${OUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/tandem-canary.XXXXXX")}"
mkdir -p "$OUT_DIR"

FAILED=0

echo "STEP phase1 enabled"
if ! "$PHASE1_SCRIPT" "$CANARY" "$OUT_DIR/phase1.pcapng"; then
  echo "canary.sh: phase1 step FAILED" >&2
  FAILED=1
fi

if [[ "$NOTIFICATION_ENABLED" == true ]]; then
  echo "STEP notification enabled"
  if ! adb shell am broadcast -a dev.tandem.companion.POST --es kind canary --es nonce "$NONCE"; then
    echo "canary.sh: notification step FAILED" >&2
    FAILED=1
  fi
fi

if [[ "$CLIPBOARD_ENABLED" == true ]]; then
  echo "STEP clipboard enabled"
  if ! adb shell am start -a android.intent.action.SEND -t text/plain \
    --es android.intent.extra.TEXT "$CANARY" -n "$SHARE_TARGET_COMPONENT"; then
    echo "canary.sh: clipboard step FAILED" >&2
    FAILED=1
  fi
fi

if [[ "$MIRROR_ENABLED" == true ]]; then
  echo "STEP mirror enabled"
  if ! adb shell am start -n "$MIRROR_CANARY_ACTIVITY" || ! adb shell input text "$CANARY"; then
    echo "canary.sh: mirror step FAILED" >&2
    FAILED=1
  fi
fi

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
exit 0
