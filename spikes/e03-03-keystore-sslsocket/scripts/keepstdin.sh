#!/usr/bin/env bash
# Opens a fifo read-write on fd 9 so stdin never reports EOF (openssl s_server
# treats a stdin EOF as an implicit quit command even with -ign_eof on this
# build), then execs the given command with that fd as its stdin.
set -euo pipefail
FIFO="$1"; shift
[[ -p "$FIFO" ]] || mkfifo "$FIFO"
exec 9<>"$FIFO"
exec "$@" <&9
