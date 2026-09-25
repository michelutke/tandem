#!/usr/bin/env bash
# mitm-scenario-name: wrong_server_cert_fails_pin_check
# mitm-scenario-role: server
# mitm-scenario-expect: handshakeRejected
# mitm-scenario-timeout: 15
#
# Self-test for the E15-08 scaffold: an impostor "Mac" stand-in presents a certificate that does
# not match what the client pinned. Mirrors the shape of the production assertion
# `mitmLab_wrongServerCertFingerprint_zeroAppBytesDelivered` (E15-10); since the real phone client
# does not exist yet, lib/pinning-client.sh stands in for its SPKI pin check (invariant 3).
# Self-contained: unlike the client-role scenario, this one stands up its own throwaway server and
# drives its own throwaway client -- both ends of this attack are stand-ins here, so it ignores
# MITM_TARGET_HOST/PORT.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$here/../lib"
workdir=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n "$server_pid" ]] && { kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null || true; }
  rm -rf "$workdir"
}
trap cleanup EXIT

"$lib/gen-cert.sh" "$workdir/pinned" pinned.tandem.test
"$lib/gen-cert.sh" "$workdir/wrong" wrong.tandem.test
pinned_fp=$("$lib/spki-fingerprint.sh" "$workdir/pinned-cert.pem")

port=$(ruby "$lib/free-port.rb")
openssl s_server -quiet -tls1_3 -alpn tandem/1 \
  -cert "$workdir/wrong-cert.pem" -key "$workdir/wrong-key.pem" \
  -accept "$port" -naccept 1 >/dev/null 2>&1 &
server_pid=$!
sleep 0.3

"$lib/pinning-client.sh" 127.0.0.1 "$port" "$pinned_fp"
