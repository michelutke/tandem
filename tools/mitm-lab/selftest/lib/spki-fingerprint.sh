#!/usr/bin/env bash
# tools/mitm-lab/selftest/lib/spki-fingerprint.sh CERT_PEM
#
# Prints the lowercase-hex SHA-256 SPKI fingerprint of a certificate: SHA-256 over the
# DER-encoded SubjectPublicKeyInfo, the same construction SPEC uses for pinning.
set -euo pipefail

openssl x509 -in "$1" -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -hex | sed 's/^.*= //'
