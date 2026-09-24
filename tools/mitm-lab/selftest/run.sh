#!/usr/bin/env bash
# tools/mitm-lab/selftest/run.sh
#
# E15-08 self-test: runs the mitm-lab scenario runner against tools/mitm-lab/selftest/scenarios/,
# demonstrating both a client-role scenario (attacking a shared TLS-1.3-only openssl s_server
# stand-in for the real Mac listener) and a server-role scenario (an impostor stand-in server,
# checked by a tiny pinning client that stands in for the real phone client). Neither the real Mac
# server nor the real Android client exists yet (E15-15); the concrete production scenarios land
# in E15-09/E15-10/E15-11/E15-20 once they do, under their own scenario directories.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workdir=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n "$server_pid" ]] && { kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null || true; }
  rm -rf "$workdir"
}
trap cleanup EXIT

"$here/lib/gen-cert.sh" "$workdir/stand-in" stand-in.tandem.test
port=$(ruby "$here/lib/free-port.rb")

openssl s_server -quiet -tls1_3 -alpn tandem/1 \
  -cert "$workdir/stand-in-cert.pem" -key "$workdir/stand-in-key.pem" \
  -accept "$port" -naccept 4 >/dev/null 2>&1 &
server_pid=$!
sleep 0.3

ruby "$here/../runner.rb" "$here/scenarios" --target-host 127.0.0.1 --target-port "$port"
