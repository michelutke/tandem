#!/usr/bin/env bash
# E00-14 tdd:
#   ci: socketUsageRule_socketInFeatureNotifications_buildFails
#   ci: socketUsageRule_sslSocketInCoreTransport_buildPasses
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
NOTIFICATIONS_FIXTURE="$ANDROID/feature/notifications/src/main/kotlin/dev/tandem/feature/notifications/SocketOnlyInTransportFixture.kt"
TRANSPORT_FIXTURE="$ANDROID/core/transport/src/main/kotlin/dev/tandem/core/transport/SocketOnlyInTransportFixture.kt"
trap 'rm -f "$NOTIFICATIONS_FIXTURE" "$TRANSPORT_FIXTURE"; rmdir -p "$(dirname "$NOTIFICATIONS_FIXTURE")" 2>/dev/null || true' EXIT
cd "$ANDROID"

mkdir -p "$(dirname "$NOTIFICATIONS_FIXTURE")"
cat > "$NOTIFICATIONS_FIXTURE" <<'KT'
package dev.tandem.feature.notifications

import java.net.Socket

internal fun openSocketFixture(host: String, port: Int): Socket = Socket(host, port)
KT
if out="$(./gradlew -q :feature:notifications:detekt 2>&1)"; then
  echo "FAIL socketUsageRule_socketInFeatureNotifications_buildFails: detekt passed" >&2
  exit 1
fi
grep -q "SocketOnlyInTransport" <<<"$out" || { echo "FAIL: detekt failed without SocketOnlyInTransport" >&2; echo "$out" >&2; exit 1; }
echo "OK socketUsageRule_socketInFeatureNotifications_buildFails"
rm -f "$NOTIFICATIONS_FIXTURE"

mkdir -p "$(dirname "$TRANSPORT_FIXTURE")"
cat > "$TRANSPORT_FIXTURE" <<'KT'
package dev.tandem.core.transport

import javax.net.ssl.SSLSocket

internal fun describeSocketFixture(socket: SSLSocket): String = socket.toString()
KT
if ! out="$(./gradlew -q :core:transport:detekt 2>&1)"; then
  echo "FAIL socketUsageRule_sslSocketInCoreTransport_buildPasses: detekt failed" >&2
  echo "$out" >&2
  exit 1
fi
echo "OK socketUsageRule_sslSocketInCoreTransport_buildPasses"
