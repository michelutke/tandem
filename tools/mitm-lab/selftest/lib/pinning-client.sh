#!/usr/bin/env bash
# tools/mitm-lab/selftest/lib/pinning-client.sh HOST PORT EXPECTED_SPKI_SHA256_HEX
#
# Tiny stand-in for the not-yet-implemented Tandem client's certificate-pin check (invariant 3:
# trust is bound to SPKI fingerprints only, never an IP or hostname). Connects over TLS 1.3,
# computes the peer leaf certificate's SPKI SHA-256 fingerprint the same way SPEC does (DER of
# SubjectPublicKeyInfo, SHA-256, hex), and refuses to proceed on any mismatch or connect failure.
# Prints exactly one "OUTCOME: <value>" line, consumed by the mitm-lab runner.
set -euo pipefail

host=$1
port=$2
expected_fp=$3

transcript=$(openssl s_client -connect "${host}:${port}" -tls1_3 -alpn tandem/1 </dev/null 2>/dev/null || true)
cert_pem=$(printf '%s\n' "$transcript" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')

if [[ -z "$cert_pem" ]]; then
  echo 'OUTCOME: handshakeRejected'
  exit 0
fi

actual_fp=$(printf '%s\n' "$cert_pem" | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -hex | sed 's/^.*= //')

if [[ "$actual_fp" == "$expected_fp" ]]; then
  echo 'OUTCOME: accepted'
else
  echo 'OUTCOME: handshakeRejected'
fi
