#!/usr/bin/env python3
"""E15-14: a fake libFuzzer-CLI-compatible target for testing run_fuzz_target.sh's crash-detection
and reproducer-saving logic independently of the real Swift/ASan target (which this toolchain may
not be able to build — see ../README.md). Understands just enough of the real CLI:

    planted_crasher.py -runs=0 -artifact_prefix=<prefix> <file> [<file> ...]
    planted_crasher.py -max_total_time=<n> -artifact_prefix=<prefix> <corpus-dir>

Deliberately "crashes" (exits 1) the moment it reads a file whose contents start with the magic
b"CRASH" prefix, first writing that file's bytes to "<prefix>crash-<sha1>" so the wrapper's
reproducer-saving path is exercised exactly as it would be against a real libFuzzer binary. Any
other input is inert: it exits 0 immediately (this fixture never actually fuzzes/mutates).
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

MAGIC_PREFIX = b"CRASH"


def main(argv: list[str]) -> int:
    artifact_prefix = "./crash-"
    paths: list[str] = []
    for arg in argv:
        if arg.startswith("-artifact_prefix="):
            artifact_prefix = arg.split("=", 1)[1]
        elif arg.startswith("-"):
            continue
        else:
            paths.append(arg)

    files: list[Path] = []
    for raw_path in paths:
        path = Path(raw_path)
        if path.is_dir():
            files.extend(sorted(p for p in path.iterdir() if p.is_file()))
        else:
            files.append(path)

    for file in files:
        data = file.read_bytes()
        if data.startswith(MAGIC_PREFIX):
            crash_path = Path(f"{artifact_prefix}crash-{hashlib.sha1(data).hexdigest()}")
            crash_path.parent.mkdir(parents=True, exist_ok=True)
            crash_path.write_bytes(data)
            print(f"==PLANTED CRASH==: {file} triggered the fixture's magic prefix", file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
