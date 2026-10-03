#!/usr/bin/env python3
"""E15-14: materializes protocol/vectors/frame-encoding.json (E01-19) as raw frame files, one per
vector, for the libFuzzer seed corpus. Reuses tools/vectors/frame_encoding.py's
`build_frame_from_vector` — the same reference builder protocol/vectors/README.md documents as
the source of truth for every language's fixture — rather than re-deriving frame bytes here.

Usage:
    tools/fuzz/libfuzzer/generate_seed_corpus.py <output-dir> [frame|envelope]

Writes one file per vector, named "<vector-id>.bin", into <output-dir> (created if absent).
With "envelope" (E71-02) each file holds only the envelope bytes, i.e. the frame without its
4-byte length prefix; frames with no envelope bytes are skipped.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

LENGTH_PREFIX_BYTES = 4
REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "tools" / "vectors"))

from frame_encoding import build_frame_from_vector  # noqa: E402


def generate(output_dir: Path, target: str = "frame") -> list[Path]:
    manifest_path = REPO_ROOT / "protocol" / "vectors" / "frame-encoding.json"
    manifest = json.loads(manifest_path.read_text())

    output_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for vector in manifest["vectors"]:
        frame = build_frame_from_vector(vector)
        if target == "envelope":
            frame = frame[LENGTH_PREFIX_BYTES:]
            if not frame:
                continue
        out_path = output_dir / f"{vector['id']}.bin"
        out_path.write_bytes(frame)
        written.append(out_path)
    return written


def main(argv: list[str]) -> int:
    if len(argv) not in (1, 2) or (len(argv) == 2 and argv[1] not in ("frame", "envelope")):
        print("usage: generate_seed_corpus.py <output-dir> [frame|envelope]", file=sys.stderr)
        return 2
    written = generate(Path(argv[0]), argv[1] if len(argv) == 2 else "frame")
    print(f"wrote {len(written)} seed corpus files to {argv[0]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
