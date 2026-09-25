#!/usr/bin/env bash
# tools/mitm-lab/selftest/lib/gen-cert.sh PREFIX COMMON_NAME
#
# Generates an ephemeral self-signed P-256 cert/key pair (matches SPEC's leaf-only P-256 check,
# decisions.md D-19) for mitm-lab self-test scenarios. Writes PREFIX-key.pem / PREFIX-cert.pem.
# Temp files only -- the caller owns and cleans up its own workdir; nothing here touches a
# keychain or any persistent store.
set -euo pipefail

prefix=$1
cn=$2

openssl ecparam -name prime256v1 -genkey -noout -out "${prefix}-key.pem"
openssl req -new -x509 -key "${prefix}-key.pem" -out "${prefix}-cert.pem" -days 1 -subj "/CN=${cn}"
