#!/usr/bin/env bash
# E71-05: stages every regression reproducer of the given targets into a replay directory.
#
#   tools/fuzz/regression/stage.sh <dest-dir> <target>...
#
# Prints the number of staged files. A target without a directory stages nothing. Exit 2: usage.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: stage.sh <dest-dir> <target>..." >&2
  exit 2
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$1"
shift

mkdir -p "$DEST"
count=0
for target in "$@"; do
  [ -d "$DIR/$target" ] || continue
  while IFS= read -r file; do
    cp "$file" "$DEST/regression-$target-$(basename "$file")"
    count=$((count + 1))
  done < <(find "$DIR/$target" -type f ! -name '.gitkeep' | sort)
done
echo "$count"
