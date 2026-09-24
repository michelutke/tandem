#!/usr/bin/env bash
# mitm-scenario-name: tls12_client_rejected_by_tls13_only_server
# mitm-scenario-role: client
# mitm-scenario-expect: handshakeRejected
# mitm-scenario-timeout: 15
#
# Self-test for the E15-08 scaffold: a TLS 1.2-only ClientHello against the shared TLS-1.3-only
# openssl s_server stand-in started by selftest/run.sh (standing in for the real Mac listener,
# which does not exist yet -- E15-15). Mirrors the shape of the production assertion
# `mitmLab_tls12OnlyClientHello_protocolVersionAlert` (E15-11), which runs the same check against
# the real listener once it exists.
set -euo pipefail

host="${MITM_TARGET_HOST:?MITM_TARGET_HOST not set}"
port="${MITM_TARGET_PORT:?MITM_TARGET_PORT not set}"

if openssl s_client -connect "${host}:${port}" -tls1_2 -alpn tandem/1 </dev/null >/dev/null 2>&1; then
  echo 'OUTCOME: accepted'
else
  echo 'OUTCOME: handshakeRejected'
fi
